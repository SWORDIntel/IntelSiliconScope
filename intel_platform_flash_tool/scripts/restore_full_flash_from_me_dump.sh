#!/bin/bash
set -e

# Full Flash Restoration from ME Dump
# Constructs a full flash image by replacing ME region in current flash
# ⚠️ CRITICAL WARNING: This restores ME firmware and optionally BIOS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_DUMP="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin"

# Flash region addresses
ME_START=$((0x00126000))
ME_END=$((0x00EC7FFF))
ME_SIZE=$((ME_END - ME_START + 1))
EXPECTED_FLASH_SIZE=$((64 * 1024 * 1024))

echo "================================================================================"
echo "FULL FLASH RESTORATION FROM ME DUMP"
echo "================================================================================"
echo "This script will:"
echo "  1. Read current full flash"
echo "  2. Replace ME region (FREG2) with old ME dump"
echo "  3. Optionally replace BIOS region if old BIOS dump available"
echo "  4. Write modified flash back"
echo ""
echo "⚠️  This will restore ME firmware to previous state (may restore HAP mode)"
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

# Check if ME dump exists
if [ ! -f "$ME_DUMP" ]; then
    echo "ERROR: ME dump not found: $ME_DUMP"
    exit 1
fi

ME_DUMP_SIZE=$(stat -c%s "$ME_DUMP")
echo "ME Dump Information:"
echo "  File: $ME_DUMP"
echo "  Size: $ME_DUMP_SIZE bytes ($(($ME_DUMP_SIZE / 1024 / 1024)) MB)"
echo "  Expected ME region: $ME_SIZE bytes ($(($ME_SIZE / 1024 / 1024)) MB)"
echo ""

# Verify ME dump is not all zeros
ME_NONZERO=$(head -c 1024 "$ME_DUMP" | tr -d '\0' | wc -c)
if [ "$ME_NONZERO" -lt 100 ]; then
    echo "ERROR: ME dump appears to be invalid (mostly zeros)"
    exit 1
fi
echo "  ✓ ME dump contains valid data"
echo ""

# Check for old BIOS dump
BIOS_DUMP="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_ifwi_parts"
BIOS_START=$((0x02000000))
BIOS_END=$((0x03FFFFFF))
BIOS_SIZE=$((BIOS_END - BIOS_START + 1))

RESTORE_BIOS="no"
if [ -d "$BIOS_DUMP" ]; then
    echo "BIOS dump directory found: $BIOS_DUMP"
    echo "  Note: IFWI parts may need to be assembled into full BIOS region"
    read -p "Attempt to restore BIOS region from IFWI parts? (yes/no): " RESTORE_BIOS
fi
echo ""

# Final confirmation
echo "================================================================================"
echo "FINAL CONFIRMATION"
echo "================================================================================"
echo "This will:"
echo "  ✓ Replace ME region (FREG2) with old ME dump"
if [ "$RESTORE_BIOS" = "yes" ]; then
    echo "  ✓ Replace BIOS region (FREG1) with old BIOS dump (if available)"
else
    echo "  - Keep current BIOS region (FREG1)"
fi
echo "  - Keep all other regions (Descriptor, EC/BMC, GbE, etc.)"
echo ""
echo "⚠️  CRITICAL WARNINGS:"
echo "  1. Ensure ME dump came from THIS EXACT SYSTEM"
echo "  2. System must be on AC power (NOT battery only)"
echo "  3. Do NOT interrupt the flash process"
echo "  4. All current BIOS settings will be preserved (unless BIOS restored)"
echo ""
read -p "Type 'RESTORE ME FROM DUMP' to confirm: " CONFIRM

if [ "$CONFIRM" != "RESTORE ME FROM DUMP" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "================================================================================"
echo "STEP 1: READING CURRENT FLASH"
echo "================================================================================"
echo "Reading current flash (this may take several minutes)..."
echo "⚠️  Note: EC/BMC region is locked, will use flash layout to exclude it"
echo ""

# Create flash layout excluding locked regions
FLASH_LAYOUT="/tmp/flash_layout_restore.txt"
cat > "$FLASH_LAYOUT" << EOF
0x00000000:0x00003fff FREG0:Descriptor
0x00124000:0x00125fff FREG3:GbE
0x00126000:0x00ec7fff FREG2:ME
0x00ec8000:0x01ffffff FREG9:DeviceExpansion
0x02000000:0x03ffffff FREG1:BIOS
EOF

echo "Flash layout created: $FLASH_LAYOUT"
echo ""

CURRENT_FLASH="/tmp/current_flash_$(date +%Y%m%d_%H%M%S).bin"
if flashrom -p internal -l "$FLASH_LAYOUT" -r "$CURRENT_FLASH" --noverify-all 2>&1 | tee /tmp/flashrom_read.log; then
    CURRENT_SIZE=$(stat -c%s "$CURRENT_FLASH")
    echo ""
    echo "✓ Current flash read successfully"
    echo "  File: $CURRENT_FLASH"
    echo "  Size: $CURRENT_SIZE bytes ($(($CURRENT_SIZE / 1024 / 1024)) MB)"
    
    if [ "$CURRENT_SIZE" -ne "$EXPECTED_FLASH_SIZE" ]; then
        echo "  ⚠ WARNING: Flash size mismatch (expected $EXPECTED_FLASH_SIZE bytes)"
    fi
else
    echo ""
    echo "✗ ERROR: Failed to read current flash"
    echo "  Check /tmp/flashrom_read.log for details"
    exit 1
fi
echo ""

echo "================================================================================"
echo "STEP 2: REPLACING ME REGION"
echo "================================================================================"
echo "Creating modified flash image with old ME region..."
echo ""

MODIFIED_FLASH="/tmp/modified_flash_$(date +%Y%m%d_%H%M%S).bin"
cp "$CURRENT_FLASH" "$MODIFIED_FLASH"
echo "  ✓ Copied current flash to: $MODIFIED_FLASH"

# Replace ME region
echo "  Replacing ME region (offset 0x$(printf "%08X" $ME_START))..."
if [ "$ME_DUMP_SIZE" -le "$ME_SIZE" ]; then
    # ME dump fits in region
    dd if="$ME_DUMP" of="$MODIFIED_FLASH" bs=1 seek=$ME_START conv=notrunc 2>/dev/null || {
        echo "  ✗ ERROR: Failed to replace ME region"
        exit 1
    }
    echo "  ✓ ME region replaced ($ME_DUMP_SIZE bytes)"
else
    # ME dump is larger, truncate to region size
    dd if="$ME_DUMP" of="$MODIFIED_FLASH" bs=1 seek=$ME_START count=$ME_SIZE conv=notrunc 2>/dev/null || {
        echo "  ✗ ERROR: Failed to replace ME region"
        exit 1
    }
    echo "  ✓ ME region replaced (truncated to $ME_SIZE bytes)"
fi

# Verify replacement
echo "  Verifying ME region replacement..."
ORIGINAL_ME_MD5=$(dd if="$CURRENT_FLASH" bs=1 skip=$ME_START count=$ME_SIZE 2>/dev/null | md5sum | cut -d' ' -f1)
NEW_ME_MD5=$(dd if="$MODIFIED_FLASH" bs=1 skip=$ME_START count=$ME_SIZE 2>/dev/null | md5sum | cut -d' ' -f1)
DUMP_MD5=$(head -c $ME_SIZE "$ME_DUMP" | md5sum | cut -d' ' -f1)

if [ "$NEW_ME_MD5" = "$DUMP_MD5" ]; then
    echo "  ✓ ME region replacement verified (MD5 match)"
else
    echo "  ⚠ WARNING: ME region MD5 mismatch"
    echo "     Original: $ORIGINAL_ME_MD5"
    echo "     New:      $NEW_ME_MD5"
    echo "     Expected: $DUMP_MD5"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi
echo ""

# Optionally replace BIOS region
if [ "$RESTORE_BIOS" = "yes" ]; then
    echo "================================================================================"
    echo "STEP 3: REPLACING BIOS REGION (OPTIONAL)"
    echo "================================================================================"
    echo "⚠️  BIOS restoration from IFWI parts is complex"
    echo "⚠️  This requires assembling IFWI parts into full BIOS region"
    echo "⚠️  This is NOT implemented - keeping current BIOS"
    echo ""
    echo "  To restore BIOS, you would need:"
    echo "    1. Full BIOS dump from old system state"
    echo "    2. Or assemble IFWI parts using Intel FIT tools"
    echo ""
fi

echo "================================================================================"
echo "STEP 4: WRITING MODIFIED FLASH"
echo "================================================================================"
echo "⚠️  This will write the modified flash (this may take several minutes)"
echo "⚠️  DO NOT INTERRUPT THIS PROCESS!"
echo ""
echo "Modified flash: $MODIFIED_FLASH"
echo "Changes: ME region replaced with old dump"
echo ""

read -p "Type 'WRITE MODIFIED FLASH' to proceed: " WRITE_CONFIRM
if [ "$WRITE_CONFIRM" != "WRITE MODIFIED FLASH" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Writing modified flash to SPI..."
if flashrom -p internal -l "$FLASH_LAYOUT" -w "$MODIFIED_FLASH" --noverify-all 2>&1 | tee /tmp/flashrom_write.log; then
    echo ""
    echo "================================================================================"
    echo "✓ FLASH RESTORATION COMPLETE"
    echo "================================================================================"
    echo ""
    echo "The ME region has been restored from: $ME_DUMP"
    echo ""
    echo "Restored:"
    echo "  ✓ ME firmware (FREG2) - may have restored HAP mode"
    echo ""
    echo "Preserved:"
    echo "  ✓ BIOS/UEFI firmware (FREG1) - unchanged"
    echo "  ✓ Flash Descriptor (FREG0) - unchanged"
    echo "  ✓ All other regions - unchanged"
    echo ""
    echo "Backup saved to: $CURRENT_FLASH"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "  1. Reboot the system for changes to take effect"
    echo "  2. Check HAP mode status after reboot"
    echo "  3. Verify ME version matches expected"
    echo ""
    echo "================================================================================"
    echo ""
    read -p "Reboot now? (yes/no): " REBOOT
    if [ "$REBOOT" = "yes" ]; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        reboot
    else
        echo "Manual reboot required for changes to take effect"
    fi
else
    echo ""
    echo "================================================================================"
    echo "✗ FLASH WRITE FAILED"
    echo "================================================================================"
    echo "The flash write operation failed. Check /tmp/flashrom_write.log for details."
    echo ""
    echo "⚠️  Your system should still be functional with the original flash."
    echo "⚠️  If the system is bricked, restore from backup:"
    echo "     flashrom -p internal -w \"$CURRENT_FLASH\""
    echo ""
    exit 1
fi
