#!/bin/bash
#
# flashrom Integration Script for DSMIL System
# Coordinates flashrom with kernel module and IFWI extraction tools
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNLOCK_DIR="${SCRIPT_DIR}/../../scripts/unlock"
IFWI_DIR="${SCRIPT_DIR}/../CCTK-MILSPEC/Firmware Patching"
OUTPUT_DIR="${SCRIPT_DIR}/dsmil_flashrom_output"

echo "================================================================="
echo "flashrom Integration with DSMIL Unlock System"
echo "================================================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (for flashrom access)"
    exit 1
fi

# Check if flashrom is available
if ! command -v flashrom >/dev/null 2>&1; then
    echo "ERROR: flashrom not found in PATH"
    echo ""
    echo "To build flashrom from source:"
    echo "  cd ${SCRIPT_DIR}"
    echo "  meson setup builddir"
    echo "  meson compile -C builddir"
    echo "  sudo meson install -C builddir"
    echo ""
    echo "Or install via package manager:"
    echo "  sudo apt install flashrom"
    exit 1
fi

echo "✓ flashrom found: $(which flashrom)"
echo "  Version: $(flashrom --version 2>&1 | head -1)"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Flash region layout (from kernel module and Intel Platform Flash Tool)
FREG0_START=0x00000000
FREG0_SIZE=0x00004000
FREG1_START=0x02000000
FREG1_SIZE=0x02000000
FREG2_START=0x00126000
FREG2_SIZE=0x00DB5FFF
FREG3_START=0x00124000
FREG3_SIZE=0x00002000

echo "================================================================="
echo "Step 1: Detecting Flash Chip"
echo "================================================================="
echo ""

if flashrom -p internal 2>&1 | tee "$OUTPUT_DIR/flashrom_detect.log"; then
    echo "✓ Flash chip detected"
else
    echo "✗ Failed to detect flash chip"
    echo "  Check $OUTPUT_DIR/flashrom_detect.log for details"
    echo ""
    echo "  Common issues:"
    echo "    - ME is active and blocking access"
    echo "    - Need different flashrom options (e.g., -p internal:laptop=this_is_not_a_laptop)"
    exit 1
fi

echo ""
echo "================================================================="
echo "Step 2: Reading Full SPI Flash"
echo "================================================================="
echo ""
echo "⚠️  WARNING: This may take several minutes and requires sufficient disk space"
echo ""

FULL_FLASH="$OUTPUT_DIR/full_flash.bin"

if flashrom -p internal -r "$FULL_FLASH" 2>&1 | tee "$OUTPUT_DIR/flashrom_read.log"; then
    FLASH_SIZE=$(stat -c%s "$FULL_FLASH" 2>/dev/null || echo "unknown")
    echo "✓ Full flash read: $FULL_FLASH ($FLASH_SIZE bytes)"
else
    echo "✗ Failed to read flash"
    echo "  Check $OUTPUT_DIR/flashrom_read.log for details"
    exit 1
fi

echo ""
echo "================================================================="
echo "Step 3: Extracting Flash Regions"
echo "================================================================="
echo ""

# Extract FREG1 (BIOS/IFWI)
echo "Extracting FREG1 (BIOS/IFWI region)..."
IFWI_BLOB="$OUTPUT_DIR/ifwi_from_flash.bin"
dd if="$FULL_FLASH" of="$IFWI_BLOB" bs=1 skip=$((FREG1_START)) count=$((FREG1_SIZE)) 2>/dev/null
IFWI_SIZE=$(stat -c%s "$IFWI_BLOB" 2>/dev/null || echo "unknown")
echo "✓ IFWI extracted: $IFWI_BLOB ($IFWI_SIZE bytes)"

# Extract FREG2 (ME Firmware)
echo "Extracting FREG2 (ME Firmware region)..."
ME_FIRMWARE="$OUTPUT_DIR/me_firmware_from_flash.bin"
dd if="$FULL_FLASH" of="$ME_FIRMWARE" bs=1 skip=$((FREG2_START)) count=$((FREG2_SIZE)) 2>/dev/null
ME_SIZE=$(stat -c%s "$ME_FIRMWARE" 2>/dev/null || echo "unknown")
echo "✓ ME firmware extracted: $ME_FIRMWARE ($ME_SIZE bytes)"

# Extract FREG0 (Flash Descriptor)
echo "Extracting FREG0 (Flash Descriptor)..."
FLASH_DESC="$OUTPUT_DIR/flash_descriptor.bin"
dd if="$FULL_FLASH" of="$FLASH_DESC" bs=1 skip=$((FREG0_START)) count=$((FREG0_SIZE)) 2>/dev/null
DESC_SIZE=$(stat -c%s "$FLASH_DESC" 2>/dev/null || echo "unknown")
echo "✓ Flash descriptor extracted: $FLASH_DESC ($DESC_SIZE bytes)"

echo ""
echo "================================================================="
echo "Step 4: Analyzing Extracted IFWI"
echo "================================================================="
echo ""

if [ -f "$IFWI_BLOB" ] && [ -f "$IFWI_DIR/ifwi_extract_with_intel_tools.py" ]; then
    echo "Analyzing extracted IFWI blob..."
    python3 "$IFWI_DIR/ifwi_extract_with_intel_tools.py" \
        --extract-from-blob "$IFWI_BLOB" \
        -o "$OUTPUT_DIR/ifwi_analysis" 2>&1 | tee "$OUTPUT_DIR/ifwi_analysis.log" || true
    echo "✓ IFWI analysis complete"
else
    echo "⚠ Skipping IFWI analysis (tool not available)"
fi

echo ""
echo "================================================================="
echo "Step 5: Coordinating with Kernel Module"
echo "================================================================="
echo ""

# Check if kernel module is loaded
if [ -f "/proc/dsmil_unlock/run_stage" ]; then
    echo "✓ DSMIL unlock kernel module detected"
    echo ""
    echo "Kernel module can read SPI controller registers:"
    echo "  - FRAP (Flash Region Access Permissions)"
    echo "  - FREG0-3 (Flash Region boundaries)"
    echo ""
    echo "To read SPI registers via kernel module:"
    echo "  echo 5 | sudo tee /proc/dsmil_unlock/run_stage"
    echo ""
    echo "⚠ WARNING: Stage 6 writes to SPI flash - DO NOT USE without backup!"
else
    echo "⚠ DSMIL unlock kernel module not loaded"
    echo "  Module location: $UNLOCK_DIR/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/"
fi

echo ""
echo "================================================================="
echo "Extraction Complete"
echo "================================================================="
echo ""
echo "Output files:"
echo "  Full flash: $FULL_FLASH"
echo "  IFWI blob: $IFWI_BLOB"
echo "  ME firmware: $ME_FIRMWARE"
echo "  Flash descriptor: $FLASH_DESC"
echo ""
echo "All files saved to: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Analyze IFWI blob with IFWI extraction tools"
echo "  2. Compare ME firmware with existing ME dumps"
echo "  3. Use extracted IFWI for AVX-512 enablement research"
echo ""
