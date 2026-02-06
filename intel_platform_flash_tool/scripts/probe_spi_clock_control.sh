#!/bin/bash
# Probe SPI Flash Controller for Clock Control Register Location
# This script reads/writes SPI controller registers to find clock divider location

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVMEM2="${SCRIPT_DIR}/../devmem2/devmem2"

SPI_MMIO_BASE=0x7c120000
SPI_DEVICE="/dev/mem"

echo "================================================================================"
echo "SPI FLASH CONTROLLER CLOCK CONTROL PROBE"
echo "================================================================================"
echo "SPI MMIO Base: $SPI_MMIO_BASE"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (for /dev/mem access)"
    exit 1
fi

# Check if devmem2 is available
if [ ! -f "$DEVMEM2" ]; then
    echo "ERROR: devmem2 not found at $DEVMEM2"
    echo "Build it with: cd tools/devmem2 && make"
    exit 1
fi

echo "[1] Reading current SPI controller registers..."
echo ""

# Read key SPI registers
HSFSTS_CTL=$("$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0000))) w 2>/dev/null | grep "Value at address" | awk '{print $NF}')
HSFCTL=$("$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0004))) w 2>/dev/null | grep "Value at address" | awk '{print $NF}')

echo "  HSFSTS_CTL (0x0000): 0x$(printf "%08X" $HSFSTS_CTL)"
echo "  HSFCTL (0x0004):     0x$(printf "%08X" $HSFCTL)"
echo ""

echo "[2] Testing HSFSTS_CTL bits 8-10 for clock divider..."
echo ""

# Save original value
ORIGINAL_HSFSTS=$HSFSTS_CTL

# Test if bits 8-10 are writable (try setting to DIV_8 = 0x300)
TEST_VALUE=$((HSFSTS_CTL & 0xFFFFF8FF | 0x300))  # Clear bits 8-10, set to 0x3

echo "  Attempting to write: 0x$(printf "%08X" $TEST_VALUE)"
"$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0000))) w $TEST_VALUE >/dev/null 2>&1
sleep 0.1

READ_BACK=$("$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0000))) w 2>/dev/null | grep "Value at address" | awk '{print $NF}')
CLOCK_BITS=$((READ_BACK & 0x700))

echo "  Read back:           0x$(printf "%08X" $READ_BACK)"
echo "  Clock bits (8-10):   0x$(printf "%03X" $CLOCK_BITS)"

# Restore original
"$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0000))) w $ORIGINAL_HSFSTS >/dev/null 2>&1

if [ $CLOCK_BITS -eq $((0x300)) ]; then
    echo "  ✓✓✓ CLOCK DIVIDER FOUND IN HSFSTS_CTL (bits 8-10) ✓✓✓"
    echo ""
    echo "  Register: HSFSTS_CTL (offset 0x0000)"
    echo "  Bits: 8-10"
    echo "  Mask: 0x700"
    echo "  Current divider: $(( (HSFSTS_CTL & 0x700) >> 8 ))"
    echo ""
    exit 0
else
    echo "  ✗ HSFSTS_CTL bits 8-10 not writable or not clock divider"
fi

echo ""
echo "[3] Testing HSFCTL bits 8-10 for clock divider..."
echo ""

ORIGINAL_HSFCTL=$HSFCTL
TEST_VALUE=$((HSFCTL & 0xFFFFF8FF | 0x300))

echo "  Attempting to write: 0x$(printf "%08X" $TEST_VALUE)"
"$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0004))) w $TEST_VALUE >/dev/null 2>&1
sleep 0.1

READ_BACK=$("$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0004))) w 2>/dev/null | grep "Value at address" | awk '{print $NF}')
CLOCK_BITS=$((READ_BACK & 0x700))

echo "  Read back:           0x$(printf "%08X" $READ_BACK)"
echo "  Clock bits (8-10):   0x$(printf "%03X" $CLOCK_BITS)"

# Restore original
"$DEVMEM2" $(printf "0x%X" $((SPI_MMIO_BASE + 0x0004))) w $ORIGINAL_HSFCTL >/dev/null 2>&1

if [ $CLOCK_BITS -eq $((0x300)) ]; then
    echo "  ✓✓✓ CLOCK DIVIDER FOUND IN HSFCTL (bits 8-10) ✓✓✓"
    echo ""
    echo "  Register: HSFCTL (offset 0x0004)"
    echo "  Bits: 8-10"
    echo "  Mask: 0x700"
    echo "  Current divider: $(( (HSFCTL & 0x700) >> 8 ))"
    echo ""
    exit 0
else
    echo "  ✗ HSFCTL bits 8-10 not writable or not clock divider"
fi

echo ""
echo "[4] Probing additional SPI registers (0x10-0x80) for clock control..."
echo ""

PROBE_OFFSETS=(0x0010 0x0014 0x0018 0x001C 0x0020 0x0024 0x0028 0x002C \
               0x0030 0x0034 0x0038 0x003C 0x0040 0x0044 0x0048 0x004C \
               0x0064 0x0068 0x006C 0x0070 0x0074 0x0078 0x007C 0x0080)

for OFFSET in "${PROBE_OFFSETS[@]}"; do
    ADDR=$((SPI_MMIO_BASE + OFFSET))
    ORIGINAL=$("$DEVMEM2" $(printf "0x%X" $ADDR) w 2>/dev/null | grep "Value at address" | awk '{print $NF}')
    
    # Try writing clock divider pattern (bits 8-10 = 0x3)
    TEST_VAL=$((ORIGINAL & 0xFFFFF8FF | 0x300))
    "$DEVMEM2" $(printf "0x%X" $ADDR) w $TEST_VAL >/dev/null 2>&1
    sleep 0.05
    
    READ_BACK=$("$DEVMEM2" $(printf "0x%X" $ADDR) w 2>/dev/null | grep "Value at address" | awk '{print $NF}')
    CLOCK_BITS=$((READ_BACK & 0x700))
    
    # Restore original
    "$DEVMEM2" $(printf "0x%X" $ADDR) w $ORIGINAL >/dev/null 2>&1
    
    if [ $CLOCK_BITS -eq $((0x300)) ]; then
        echo "  ✓✓✓ CLOCK DIVIDER FOUND AT OFFSET $OFFSET ✓✓✓"
        echo ""
        echo "  Register offset: $OFFSET"
        echo "  Full address: 0x$(printf "%08X" $ADDR)"
        echo "  Bits: 8-10"
        echo "  Mask: 0x700"
        echo "  Current value: 0x$(printf "%08X" $ORIGINAL)"
        echo ""
        exit 0
    fi
done

echo "  ✗ Clock divider register not found in probed registers"
echo ""
echo "[5] Summary:"
echo "  HSFSTS_CTL (0x0000): 0x$(printf "%08X" $HSFSTS_CTL)"
echo "  HSFCTL (0x0004):     0x$(printf "%08X" $HSFCTL)"
echo ""
echo "  ⚠ Clock divider location not confirmed via probing"
echo "  Recommendation: Use HSFSTS_CTL bits 8-10 as default (standard Intel SPI location)"
echo ""
