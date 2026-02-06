#!/bin/bash
set -e

# Full SPI Flash Restoration Script
# ⚠️ CRITICAL WARNING: This script writes the ENTIRE SPI flash
# ⚠️ BRICK RISK: This will restore BOTH BIOS and ME firmware
# ⚠️ ONLY USE: If you have a verified full flash dump from this exact system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLASH_DUMP="${SCRIPT_DIR}/flashrom_dump.bin"

# Expected flash size (64MB for GigaDevice GD25LR512ME)
EXPECTED_FLASH_SIZE=$((64 * 1024 * 1024))

echo "================================================================================"
echo "FULL SPI FLASH RESTORATION SCRIPT"
echo "================================================================================"
echo "⚠️  CRITICAL WARNING: This will restore the ENTIRE SPI flash!"
echo "⚠️  This includes:"
echo "     - BIOS/UEFI firmware (FREG1: 0x02000000-0x03FFFFFF)"
echo "     - ME firmware (FREG2: 0x00126000-0x00EC7FFF)"
echo "     - Flash Descriptor (FREG0: 0x00000000-0x00003FFF)"
echo "     - EC/BMC firmware (FREG8: 0x00004000-0x00123FFF)"
echo "     - GbE firmware (FREG3: 0x00124000-0x00125FFF)"
echo "     - Device Expansion (FREG9: 0x00EC8000-0x01FFFFFF)"
echo ""
echo "⚠️  THIS WILL RESTORE THE SYSTEM TO THE STATE WHEN THE DUMP WAS CREATED"
echo "⚠️  This can PERMANENTLY DAMAGE your system if the dump is incorrect!"
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

# Check if flash dump exists
if [ ! -f "$FLASH_DUMP" ]; then
    echo "ERROR: Flash dump not found: $FLASH_DUMP"
    echo ""
    echo "Expected location: tools/intel_platform_flash_tool/flashrom_dump.bin"
    exit 1
fi

FLASH_SIZE=$(stat -c%s "$FLASH_DUMP")
echo "Flash Dump Information:"
echo "  File: $FLASH_DUMP"
echo "  Size: $FLASH_SIZE bytes ($(($FLASH_SIZE / 1024 / 1024)) MB)"
echo "  Expected: $EXPECTED_FLASH_SIZE bytes ($(($EXPECTED_FLASH_SIZE / 1024 / 1024)) MB)"
echo ""

# Verify flash dump size
if [ "$FLASH_SIZE" -ne "$EXPECTED_FLASH_SIZE" ]; then
    echo "⚠️  WARNING: Flash dump size does not match expected size"
    echo "  Expected: $EXPECTED_FLASH_SIZE bytes"
    echo "  Actual: $FLASH_SIZE bytes"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

# Verify flash dump is not all zeros
echo "Verifying flash dump integrity..."
NONZERO_COUNT=$(od -An -td1 "$FLASH_DUMP" | awk '{for(i=1;i<=NF;i++) if($i!=0) count++} END {print count+0}')
NONZERO_PERCENT=$((NONZERO_COUNT * 100 / $FLASH_SIZE))
echo "  Non-zero bytes: $NONZERO_COUNT / $FLASH_SIZE ($NONZERO_PERCENT%)"

if [ "$NONZERO_PERCENT" -lt 5 ]; then
    echo "  ✗ ERROR: Flash dump appears to be mostly zeros (invalid dump)"
    echo "  The dump may not have been read correctly"
    exit 1
elif [ "$NONZERO_PERCENT" -lt 20 ]; then
    echo "  ⚠ WARNING: Flash dump has low data density"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
else
    echo "  ✓ Flash dump contains valid data"
fi
echo ""

# Check flash regions
echo "Flash Region Analysis:"
echo "====================="
ME_START=$((0x00126000))
ME_END=$((0x00EC7FFF))
BIOS_START=$((0x02000000))
BIOS_END=$((0x03FFFFFF))

echo "  ME Region (FREG2): 0x$(printf "%08X" $ME_START) - 0x$(printf "%08X" $ME_END)"
ME_DATA=$(dd if="$FLASH_DUMP" bs=1 skip=$ME_START count=256 2>/dev/null | tr -d '\0' | wc -c)
echo "    Non-zero bytes in first 256 bytes: $ME_DATA / 256"
if [ "$ME_DATA" -lt 10 ]; then
    echo "    ⚠ ME region appears to be zeros"
else
    echo "    ✓ ME region contains data"
fi

echo "  BIOS Region (FREG1): 0x$(printf "%08X" $BIOS_START) - 0x$(printf "%08X" $BIOS_END)"
BIOS_DATA=$(dd if="$FLASH_DUMP" bs=1 skip=$BIOS_START count=256 2>/dev/null | tr -d '\0' | wc -c)
echo "    Non-zero bytes in first 256 bytes: $BIOS_DATA / 256"
if [ "$BIOS_DATA" -lt 10 ]; then
    echo "    ⚠ BIOS region appears to be zeros"
else
    echo "    ✓ BIOS region contains data"
fi
echo ""

# Final confirmation
echo "================================================================================"
echo "FINAL CONFIRMATION"
echo "================================================================================"
echo "You are about to restore the ENTIRE SPI flash from:"
echo "  Source: $FLASH_DUMP"
echo ""
echo "This will:"
echo "  ✓ Restore BIOS/UEFI firmware to previous state"
echo "  ✓ Restore ME firmware to previous state (may restore HAP mode)"
echo "  ✓ Restore all flash regions (Descriptor, EC/BMC, GbE, etc.)"
echo ""
echo "⚠️  CRITICAL WARNINGS:"
echo "  1. Ensure this dump came from THIS EXACT SYSTEM"
echo "  2. Ensure the system is connected to AC power (NOT battery only)"
echo "  3. Do NOT interrupt the flash process (can brick the system)"
echo "  4. The system will reboot after restoration"
echo "  5. All current BIOS settings will be lost"
echo ""
read -p "Type 'RESTORE FULL FLASH' to confirm: " CONFIRM

if [ "$CONFIRM" != "RESTORE FULL FLASH" ]; then
    echo "Aborted. Confirmation text did not match."
    exit 1
fi

echo ""
echo "================================================================================"
echo "CREATING BACKUP OF CURRENT FLASH"
echo "================================================================================"
echo "⚠️  Creating backup before restoration (this may take several minutes)..."
echo ""

BACKUP_FILE="/tmp/flash_backup_$(date +%Y%m%d_%H%M%S).bin"
echo "Backup file: $BACKUP_FILE"
echo ""

if flashrom -p internal -r "$BACKUP_FILE" 2>&1 | tee /tmp/flashrom_backup.log; then
    BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE")
    echo ""
    echo "✓ Backup created successfully"
    echo "  File: $BACKUP_FILE"
    echo "  Size: $BACKUP_SIZE bytes ($(($BACKUP_SIZE / 1024 / 1024)) MB)"
    echo ""
    echo "⚠️  IMPORTANT: Save this backup file to a safe location!"
    echo "   If restoration fails, you can restore from this backup"
    echo ""
else
    echo ""
    echo "⚠️  WARNING: Backup failed (check /tmp/flashrom_backup.log)"
    echo "   Flash may be protected or read-only"
    read -p "Continue with restoration anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

echo ""
echo "================================================================================"
echo "RESTORING FULL SPI FLASH"
echo "================================================================================"
echo "⚠️  This will write the entire flash (this may take several minutes)"
echo "⚠️  DO NOT INTERRUPT THIS PROCESS!"
echo ""
echo "Source: $FLASH_DUMP"
echo "Target: SPI flash chip (internal)"
echo ""

# Verify flashrom can detect the chip
echo "Detecting flash chip..."
if ! flashrom -p internal 2>&1 | grep -q "Found.*flash"; then
    echo "⚠️  WARNING: Flash chip detection may have failed"
    echo "   Check flashrom output above"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi
echo ""

# Write the flash
echo "Writing flash dump to SPI flash..."
echo "Command: flashrom -p internal -w \"$FLASH_DUMP\""
echo ""

if flashrom -p internal -w "$FLASH_DUMP" 2>&1 | tee /tmp/flashrom_write.log; then
    echo ""
    echo "================================================================================"
    echo "✓ FULL FLASH RESTORATION COMPLETE"
    echo "================================================================================"
    echo ""
    echo "The entire SPI flash has been restored from: $FLASH_DUMP"
    echo ""
    echo "Restored regions:"
    echo "  ✓ BIOS/UEFI firmware (FREG1)"
    echo "  ✓ ME firmware (FREG2) - may have restored HAP mode"
    echo "  ✓ Flash Descriptor (FREG0)"
    echo "  ✓ EC/BMC firmware (FREG8)"
    echo "  ✓ GbE firmware (FREG3)"
    echo "  ✓ Device Expansion (FREG9)"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "  1. The system will need to be rebooted for changes to take effect"
    echo "  2. BIOS settings have been reset to the dump's state"
    echo "  3. Check HAP mode status after reboot"
    echo "  4. Verify ME version matches expected (0:18.0.18.2571)"
    echo ""
    echo "Backup saved to: $BACKUP_FILE"
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
    echo "     flashrom -p internal -w \"$BACKUP_FILE\""
    echo ""
    exit 1
fi
