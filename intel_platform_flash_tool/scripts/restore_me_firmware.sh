#!/bin/bash
set -e

# ME Firmware Restoration Script
# ⚠️ CRITICAL WARNING: This script writes ME firmware to SPI flash
# ⚠️ BRICK RISK: Incorrect ME firmware can permanently damage the system
# ⚠️ ONLY USE: If you have a verified ME dump from this exact system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_DUMP_DIR="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_me_dumps"

# ME Region (FREG2) from flashrom analysis
ME_REGION_START=0x00126000
ME_REGION_END=0x00EC7FFF
ME_REGION_SIZE=$((0x00EC7FFF - 0x00126000 + 1))

echo "================================================================================"
echo "ME FIRMWARE RESTORATION SCRIPT"
echo "================================================================================"
echo "⚠️  CRITICAL WARNING: This operation can BRICK your system!"
echo "⚠️  Only proceed if you have a verified ME dump from this exact system"
echo "================================================================================"
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check if flashrom is installed
if ! command -v flashrom &> /dev/null; then
    echo "ERROR: flashrom is not installed"
    echo "Install with: sudo apt install flashrom"
    exit 1
fi

# List available ME dumps
echo "Available ME dumps:"
echo "=================="
ls -lh "${ME_DUMP_DIR}"/*.bin 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || {
    echo "  No ME dumps found in ${ME_DUMP_DIR}"
    exit 1
}
echo ""

# Prompt for dump file
read -p "Enter ME dump filename (e.g., me_dump_16mb.bin): " DUMP_FILE
DUMP_PATH="${ME_DUMP_DIR}/${DUMP_FILE}"

if [ ! -f "${DUMP_PATH}" ]; then
    echo "ERROR: ME dump file not found: ${DUMP_PATH}"
    exit 1
fi

DUMP_SIZE=$(stat -c%s "${DUMP_PATH}")
echo ""
echo "ME Dump Information:"
echo "  File: ${DUMP_PATH}"
echo "  Size: ${DUMP_SIZE} bytes ($(($DUMP_SIZE / 1024 / 1024)) MB)"
echo "  ME Region: ${ME_REGION_START}-${ME_REGION_END} ($(($ME_REGION_SIZE / 1024 / 1024)) MB)"
echo ""

# Verify dump is not all zeros
echo "Verifying dump integrity..."
FIRST_1KB=$(head -c 1024 "${DUMP_PATH}")
if [ "$(echo "$FIRST_1KB" | tr -d '\0' | wc -c)" -eq 0 ]; then
    echo "ERROR: ME dump appears to be all zeros (invalid dump)"
    exit 1
fi
echo "  ✓ Dump contains non-zero data"

# Check dump size matches ME region
if [ "$DUMP_SIZE" -ne "$ME_REGION_SIZE" ]; then
    echo "⚠️  WARNING: Dump size ($DUMP_SIZE bytes) does not match ME region size ($ME_REGION_SIZE bytes)"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

# Final confirmation
echo ""
echo "================================================================================"
echo "FINAL CONFIRMATION"
echo "================================================================================"
echo "You are about to write ME firmware to SPI flash:"
echo "  Source: ${DUMP_PATH}"
echo "  Target: ME Region (FREG2) at ${ME_REGION_START}-${ME_REGION_END}"
echo ""
echo "⚠️  THIS CAN PERMANENTLY DAMAGE YOUR SYSTEM IF THE DUMP IS INCORRECT"
echo "⚠️  Ensure this dump came from THIS EXACT SYSTEM"
echo "⚠️  Ensure the system is connected to power (not battery only)"
echo ""
read -p "Type 'RESTORE ME FIRMWARE' to confirm: " CONFIRM

if [ "$CONFIRM" != "RESTORE ME FIRMWARE" ]; then
    echo "Aborted. Confirmation text did not match."
    exit 1
fi

echo ""
echo "================================================================================"
echo "RESTORING ME FIRMWARE"
echo "================================================================================"

# Method 1: Use flashrom to write ME region directly
echo ""
echo "Method 1: Direct ME region write with flashrom"
echo "-----------------------------------------------"

# Create a flash layout file for ME region only
FLASH_LAYOUT="/tmp/me_restore_layout.txt"
cat > "${FLASH_LAYOUT}" << EOF
# Flash layout for ME firmware restoration
# ME Region (FREG2): ${ME_REGION_START}-${ME_REGION_END}
${ME_REGION_START}:${ME_REGION_END} FREG2:ME
EOF

echo "Flash layout created: ${FLASH_LAYOUT}"
echo ""

# Attempt to write ME region
echo "Attempting to write ME firmware to SPI flash..."
echo "Command: flashrom -p internal -l ${FLASH_LAYOUT} -w ${DUMP_PATH} -i FREG2"
echo ""

# Note: flashrom -w writes the entire flash, but -i limits to specific region
# However, we need to create a full flash image with the ME region replaced
# This is complex, so we'll try the direct approach first

# Create a backup of current flash first
BACKUP_FILE="/tmp/flash_backup_$(date +%Y%m%d_%H%M%S).bin"
echo "Creating backup of current flash..."
if flashrom -p internal -r "${BACKUP_FILE}" 2>&1 | tee /tmp/flashrom_backup.log; then
    echo "  ✓ Backup created: ${BACKUP_FILE}"
else
    echo "  ⚠️  Backup failed (may be protected, continuing anyway)"
fi
echo ""

# For ME region write, we need to use flashrom's region-specific write
# However, flashrom doesn't support direct region writes easily
# We may need to use Intel Platform Flash Tool or a custom approach

echo "================================================================================"
echo "ME FIRMWARE RESTORATION OPTIONS"
echo "================================================================================"
echo ""
echo "Option 1: Use flashrom with full flash image (RECOMMENDED)"
echo "  - Requires creating a full flash image with ME region replaced"
echo "  - Safer: Can verify before writing"
echo ""
echo "Option 2: Use Intel Platform Flash Tool Lite"
echo "  - May support direct ME region flashing"
echo "  - Requires FLS file format"
echo ""
echo "Option 3: Kernel module direct SPI write (ADVANCED)"
echo "  - Most direct method"
echo "  - Highest risk"
echo ""

read -p "Select option (1/2/3) or 'abort': " OPTION

case "$OPTION" in
    1)
        echo ""
        echo "Option 1: Full flash image method"
        echo "================================"
        echo "This method requires:"
        echo "  1. Reading current full flash"
        echo "  2. Replacing ME region in the image"
        echo "  3. Writing modified image back"
        echo ""
        echo "⚠️  This is the safest method but requires full flash access"
        echo ""
        
        # Read current flash
        CURRENT_FLASH="/tmp/current_flash_$(date +%Y%m%d_%H%M%S).bin"
        echo "Reading current flash (this may take several minutes)..."
        if flashrom -p internal -r "${CURRENT_FLASH}" 2>&1 | tee /tmp/flashrom_read.log; then
            echo "  ✓ Current flash read: ${CURRENT_FLASH}"
            
            # Replace ME region in flash image
            MODIFIED_FLASH="/tmp/modified_flash_$(date +%Y%m%d_%H%M%S).bin"
            echo "Replacing ME region in flash image..."
            cp "${CURRENT_FLASH}" "${MODIFIED_FLASH}"
            
            # Calculate offsets (ME region starts at 0x00126000 in SPI flash)
            ME_OFFSET=$((0x00126000))
            dd if="${DUMP_PATH}" of="${MODIFIED_FLASH}" bs=1 seek=${ME_OFFSET} conv=notrunc 2>/dev/null || {
                echo "ERROR: Failed to replace ME region in flash image"
                exit 1
            }
            echo "  ✓ ME region replaced in flash image: ${MODIFIED_FLASH}"
            
            # Verify the replacement
            echo "Verifying ME region replacement..."
            ORIGINAL_ME=$(dd if="${CURRENT_FLASH}" bs=1 skip=${ME_OFFSET} count=${DUMP_SIZE} 2>/dev/null | md5sum | cut -d' ' -f1)
            NEW_ME=$(dd if="${MODIFIED_FLASH}" bs=1 skip=${ME_OFFSET} count=${DUMP_SIZE} 2>/dev/null | md5sum | cut -d' ' -f1)
            DUMP_MD5=$(md5sum "${DUMP_PATH}" | cut -d' ' -f1)
            
            if [ "$NEW_ME" = "$DUMP_MD5" ]; then
                echo "  ✓ ME region replacement verified (MD5 match)"
            else
                echo "  ⚠️  WARNING: ME region replacement verification failed"
                echo "     Original ME MD5: ${ORIGINAL_ME}"
                echo "     New ME MD5: ${NEW_ME}"
                echo "     Dump MD5: ${DUMP_MD5}"
                read -p "Continue anyway? (yes/no): " CONTINUE
                if [ "$CONTINUE" != "yes" ]; then
                    echo "Aborted."
                    exit 1
                fi
            fi
            
            # Final write confirmation
            echo ""
            echo "================================================================================"
            echo "READY TO WRITE MODIFIED FLASH"
            echo "================================================================================"
            echo "Modified flash image: ${MODIFIED_FLASH}"
            echo "ME region: ${ME_REGION_START}-${ME_REGION_END}"
            echo ""
            read -p "Type 'WRITE FLASH' to proceed with flash write: " WRITE_CONFIRM
            
            if [ "$WRITE_CONFIRM" != "WRITE FLASH" ]; then
                echo "Aborted."
                exit 1
            fi
            
            # Write modified flash
            echo ""
            echo "Writing modified flash to SPI..."
            if flashrom -p internal -w "${MODIFIED_FLASH}" 2>&1 | tee /tmp/flashrom_write.log; then
                echo ""
                echo "================================================================================"
                echo "✓ ME FIRMWARE RESTORATION COMPLETE"
                echo "================================================================================"
                echo "The ME firmware has been restored from: ${DUMP_PATH}"
                echo ""
                echo "⚠️  IMPORTANT: Reboot the system for changes to take effect"
                echo "⚠️  The system may behave differently after ME firmware restoration"
                echo ""
            else
                echo ""
                echo "================================================================================"
                echo "✗ FLASH WRITE FAILED"
                echo "================================================================================"
                echo "The flash write operation failed. Check /tmp/flashrom_write.log for details."
                echo "Your system should still be functional with the original ME firmware."
                exit 1
            fi
        else
            echo "  ✗ Failed to read current flash"
            echo "  Check /tmp/flashrom_read.log for details"
            exit 1
        fi
        ;;
    2)
        echo ""
        echo "Option 2: Intel Platform Flash Tool Lite"
        echo "========================================"
        echo "This method requires converting the ME dump to FLS format"
        echo "See: tools/intel_platform_flash_tool/ANALYSIS_SUMMARY.md"
        echo ""
        echo "⚠️  Intel Platform Flash Tool Lite may not support direct ME region flashing"
        echo "⚠️  This option is not fully implemented"
        exit 1
        ;;
    3)
        echo ""
        echo "Option 3: Kernel module direct SPI write"
        echo "========================================"
        echo "⚠️  This is the most dangerous method"
        echo "⚠️  Requires loading a kernel module with SPI write capability"
        echo "⚠️  Not implemented in current kernel modules"
        echo ""
        echo "This would require:"
        echo "  1. Kernel module with SPI controller access"
        echo "  2. Direct SPI flash write commands"
        echo "  3. Bypassing ME write protection"
        echo ""
        echo "⚠️  This option is not recommended and not implemented"
        exit 1
        ;;
    abort|*)
        echo "Aborted."
        exit 1
        ;;
esac

echo ""
echo "================================================================================"
echo "RESTORATION COMPLETE"
echo "================================================================================"
