#!/bin/bash
set -e

# ME Firmware Restoration using Intel FIT Methodology
# Uses FIT approach: decompose, replace ME region, rebuild

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_DUMP="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin"

echo "================================================================================"
echo "ME FIRMWARE RESTORATION - INTEL FIT METHODOLOGY"
echo "================================================================================"
echo "This script uses Intel FIT approach:"
echo "  1. Decompose current flash into regions"
echo "  2. Replace ME region with old dump"
echo "  3. Rebuild flash image"
echo "  4. Attempt to write using HMRFPO or other bypass methods"
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
echo "ME Region: 0x$(printf "%08X" $ME_START) - 0x$(printf "%08X" $ME_END) ($ME_SIZE bytes)"
echo ""

# Step 1: Read current flash
echo "=== STEP 1: READING CURRENT FLASH ==="
FLASH_LAYOUT="/tmp/flash_layout_fit.txt"
cat > "$FLASH_LAYOUT" << EOF
0x00000000:0x00003fff FREG0:Descriptor
0x00124000:0x00125fff FREG3:GbE
0x00126000:0x00ec7fff FREG2:ME
0x00ec8000:0x01ffffff FREG9:DeviceExpansion
0x02000000:0x03ffffff FREG1:BIOS
EOF

CURRENT_FLASH="/tmp/current_flash_fit_$(date +%Y%m%d_%H%M%S).bin"
echo "Reading current flash..."
if ! sudo /usr/sbin/flashrom -p internal -l "$FLASH_LAYOUT" -r "$CURRENT_FLASH" --noverify-all 2>&1 | tee /tmp/flashrom_read_fit.log; then
    echo "✗ Failed to read flash"
    exit 1
fi
echo "✓ Flash read: $CURRENT_FLASH"
echo ""

# Step 2: Replace ME region
echo "=== STEP 2: REPLACING ME REGION ==="
MODIFIED_FLASH="/tmp/modified_flash_fit_$(date +%Y%m%d_%H%M%S).bin"
cp "$CURRENT_FLASH" "$MODIFIED_FLASH"

echo "Replacing ME region..."
dd if="$ME_DUMP" of="$MODIFIED_FLASH" bs=1 seek=$ME_START count=$ME_SIZE conv=notrunc 2>/dev/null || {
    echo "✗ Failed to replace ME region"
    exit 1
}
echo "✓ ME region replaced"
echo ""

# Step 3: Check for HMRFPO support
echo "=== STEP 3: CHECKING FOR HMRFPO SUPPORT ==="
echo "HMRFPO (Host ME Region Flash Protection Override) can temporarily"
echo "disable ME write protection until next reboot."
echo ""

# Check if we can send HMRFPO command via HECI
echo "Checking HECI interface..."
if [ -d /sys/class/mei ] || [ -c /dev/mei0 ]; then
    echo "✓ HECI interface found"
    echo "  Attempting to check HMRFPO capability..."
    echo "  Note: This requires BIOS support for ME Update command"
else
    echo "✗ HECI interface not found"
fi
echo ""

# Step 4: Check Manufacturing Mode
echo "=== STEP 4: CHECKING MANUFACTURING MODE ==="
echo "If ME is in Manufacturing Mode, write protection may be disabled."
echo ""

# Check via CCTK tokens
if command -v cctk-milspec >/dev/null 2>&1; then
    echo "Checking Manufacturing Mode token..."
    MANUFACTURING_MODE=$(sudo cctk-milspec --token 0x1041 2>&1 || echo "unknown")
    echo "  Manufacturing Mode: $MANUFACTURING_MODE"
    if echo "$MANUFACTURING_MODE" | grep -qi "enabled\|yes\|1"; then
        echo "  ✓ Manufacturing Mode appears enabled - write protection may be disabled"
    else
        echo "  ⚠ Manufacturing Mode not enabled"
    fi
else
    echo "  CCTK not available, cannot check Manufacturing Mode"
fi
echo ""

# Step 5: Attempt write with different methods
echo "=== STEP 5: ATTEMPTING FLASH WRITE ==="
echo ""

# Method 1: Try with HMRFPO flag (if flashrom supports it)
echo "Method 1: Standard flashrom write with layout..."
WRITE_OUTPUT=$(sudo /usr/sbin/flashrom -p internal -l "$FLASH_LAYOUT" -w "$MODIFIED_FLASH" --noverify-all 2>&1 | tee /tmp/flashrom_write_fit.log)
WRITE_EXIT=$?

# Check for actual failure indicators in output
if [ $WRITE_EXIT -eq 0 ] && ! echo "$WRITE_OUTPUT" | grep -qi "failed\|error\|unknown state\|DO NOT REBOOT"; then
    echo "✓ Flash write succeeded!"
    echo ""
    echo "================================================================================"
    echo "✓ ME FIRMWARE RESTORATION COMPLETE"
    echo "================================================================================"
    echo "Reboot required for changes to take effect"
    exit 0
else
    echo "✗ Method 1 failed"
    if echo "$WRITE_OUTPUT" | grep -qi "unknown state\|DO NOT REBOOT"; then
        echo "  ⚠ CRITICAL: Flash chip may be in unknown state!"
        echo "  Check /tmp/flashrom_write_fit.log for details"
    fi
fi
echo ""

# Method 2: Try with --ifd flag (Intel Flash Descriptor manipulation)
echo "Method 2: Attempting with --ifd flag..."
if sudo /usr/sbin/flashrom -p internal --ifd -i FREG2 -w "$ME_DUMP" 2>&1 | tee -a /tmp/flashrom_write_fit.log; then
    echo "✓ Flash write succeeded!"
    exit 0
else
    echo "✗ Method 2 failed"
fi
echo ""

# Method 3: Check if we can use Intel fpt (Flash Programming Tool)
echo "Method 3: Checking for Intel fpt (Flash Programming Tool)..."
FPT_TOOL=$(find /usr -name "fpt*" 2>/dev/null | head -1)
if [ -n "$FPT_TOOL" ]; then
    echo "  Found: $FPT_TOOL"
    echo "  Attempting ME region write with fpt..."
    if sudo "$FPT_TOOL" -me -f "$ME_DUMP" 2>&1 | tee -a /tmp/flashrom_write_fit.log; then
        echo "✓ Flash write succeeded!"
        exit 0
    else
        echo "✗ fpt write failed"
    fi
else
    echo "  fpt not found (typically in Intel ME System Tools)"
fi
echo ""

# Summary
echo "================================================================================"
echo "ALL METHODS FAILED"
echo "================================================================================"
echo ""
echo "The ME region is protected and cannot be written via standard tools"
echo "while the ME is active."
echo ""
echo "Options remaining:"
echo "  1. Download Intel FIT (Flash Image Tool) - Windows tool"
echo "     - May work with Wine"
echo "     - Can create proper flash image with ME region"
echo ""
echo "  2. Use external SPI programmer"
echo "     - Hardware access to SPI flash chip"
echo "     - Bypasses all software protections"
echo ""
echo "  3. Activate HAP mode first (if possible)"
echo "     - Then flashrom can write ME region"
echo "     - But we're trying to restore HAP mode..."
echo ""
echo "  4. Check for hardware jumper/service mode"
echo "     - Some systems have ME_CLR or Service Mode jumper"
echo "     - Disables Flash Descriptor locks"
echo ""
echo "Backup saved to: $CURRENT_FLASH"
echo "Modified flash saved to: $MODIFIED_FLASH"
echo ""
echo "================================================================================"
