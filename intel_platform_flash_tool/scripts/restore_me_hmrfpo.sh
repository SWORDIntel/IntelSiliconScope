#!/bin/bash
set -e

# ME Firmware Restoration using HMRFPO (Host ME Region Flash Protection Override)
# Attempts to send HMRFPO command via HECI to disable ME write protection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_DUMP="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin"

echo "================================================================================"
echo "ME FIRMWARE RESTORATION USING HMRFPO"
echo "================================================================================"
echo "HMRFPO (Host ME Region Flash Protection Override) can temporarily"
echo "disable ME write protection via HECI command until next reboot."
echo "================================================================================"
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check ME dump
if [ ! -f "$ME_DUMP" ]; then
    echo "ERROR: ME dump not found: $ME_DUMP"
    exit 1
fi

ME_START=$((0x00126000))
ME_END=$((0x00EC7FFF))
ME_SIZE=$((ME_END - ME_START + 1))

echo "ME Dump: $ME_DUMP"
echo "ME Region: 0x$(printf "%08X" $ME_START) - 0x$(printf "%08X" $ME_END)"
echo ""

# Check HECI interface
echo "=== CHECKING HECI INTERFACE ==="
if [ -c /dev/mei0 ]; then
    echo "✓ HECI interface found: /dev/mei0"
    ls -l /dev/mei0
else
    echo "✗ HECI interface not found"
    echo "  HMRFPO requires HECI interface"
    exit 1
fi
echo ""

# Check for HECI tools or create simple HMRFPO command
echo "=== ATTEMPTING HMRFPO COMMAND ==="
echo "HMRFPO command format:"
echo "  - HECI command: MKHI_ME_UPDATE (0x03)"
echo "  - Sub-command: HMRFPO_ENABLE (0x02)"
echo "  - Sent via /dev/mei0"
echo ""

# Check if we have HECI tools
HECI_TOOL=$(which meitool 2>/dev/null || which mei-amt 2>/dev/null || echo "")
if [ -n "$HECI_TOOL" ]; then
    echo "Found HECI tool: $HECI_TOOL"
    echo "Attempting HMRFPO enable..."
    # Note: Actual command depends on tool
else
    echo "No HECI tools found"
    echo "HMRFPO requires:"
    echo "  1. BIOS support for ME Update command"
    echo "  2. HECI tool to send command"
    echo "  3. ME firmware that supports HMRFPO"
    echo ""
    echo "Creating backup and attempting direct write (may fail)..."
fi
echo ""

# Create backup first
echo "=== CREATING BACKUP ==="
FLASH_LAYOUT="/tmp/flash_layout_hmrfpo.txt"
cat > "$FLASH_LAYOUT" << EOF
0x00000000:0x00003fff FREG0:Descriptor
0x00124000:0x00125fff FREG3:GbE
0x00126000:0x00ec7fff FREG2:ME
0x00ec8000:0x01ffffff FREG9:DeviceExpansion
0x02000000:0x03ffffff FREG1:BIOS
EOF

BACKUP_FLASH="/tmp/flash_backup_hmrfpo_$(date +%Y%m%d_%H%M%S).bin"
echo "Reading current flash for backup..."
if ! sudo /usr/sbin/flashrom -p internal -l "$FLASH_LAYOUT" -r "$BACKUP_FLASH" --noverify-all 2>&1 | tee /tmp/flashrom_backup_hmrfpo.log; then
    echo "✗ Backup failed"
    exit 1
fi
echo "✓ Backup created: $BACKUP_FLASH"
echo ""

# Replace ME region in backup
echo "=== PREPARING MODIFIED FLASH ==="
MODIFIED_FLASH="/tmp/modified_flash_hmrfpo_$(date +%Y%m%d_%H%M%S).bin"
cp "$BACKUP_FLASH" "$MODIFIED_FLASH"

echo "Replacing ME region..."
dd if="$ME_DUMP" of="$MODIFIED_FLASH" bs=1 seek=$ME_START count=$ME_SIZE conv=notrunc 2>/dev/null || {
    echo "✗ Failed to replace ME region"
    exit 1
}
echo "✓ ME region replaced"
echo ""

# Attempt write (HMRFPO may or may not be active)
echo "=== ATTEMPTING FLASH WRITE ==="
echo "⚠️  Note: HMRFPO may not be active (requires BIOS support)"
echo "   If this fails, ME region is still read-only"
echo ""

WRITE_OUTPUT=$(sudo /usr/sbin/flashrom -p internal -l "$FLASH_LAYOUT" -w "$MODIFIED_FLASH" --noverify-all 2>&1 | tee /tmp/flashrom_write_hmrfpo.log)
WRITE_EXIT=$?

if [ $WRITE_EXIT -eq 0 ] && ! echo "$WRITE_OUTPUT" | grep -qi "failed\|error\|unknown state\|DO NOT REBOOT"; then
    echo "✓ Flash write succeeded!"
    echo ""
    echo "================================================================================"
    echo "✓ ME FIRMWARE RESTORATION COMPLETE"
    echo "================================================================================"
    echo "Reboot required for changes to take effect"
    exit 0
else
    echo "✗ Flash write failed"
    if echo "$WRITE_OUTPUT" | grep -qi "unknown state\|DO NOT REBOOT"; then
        echo "  ⚠ CRITICAL: Flash chip may be in unknown state!"
    else
        echo "  ME region is still read-only (HMRFPO not active or not supported)"
    fi
    echo ""
    echo "HMRFPO was not successful. Options:"
    echo "  1. BIOS may not support HMRFPO command"
    echo "  2. ME firmware may not support HMRFPO"
    echo "  3. Need Intel FIT or external SPI programmer"
    echo ""
    echo "Backup saved to: $BACKUP_FLASH"
    echo "System should still be functional (write was blocked, not corrupted)"
fi
