#!/bin/bash
# ME Dump Structure Analyzer
# Analyzes the structure of ME firmware dumps to verify validity

DUMP_FILE="${1:-docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin}"

if [ ! -f "$DUMP_FILE" ]; then
    echo "ERROR: ME dump file not found: $DUMP_FILE"
    exit 1
fi

DUMP_SIZE=$(stat -c%s "$DUMP_FILE")
echo "================================================================================"
echo "ME DUMP STRUCTURE ANALYSIS"
echo "================================================================================"
echo "File: $DUMP_FILE"
echo "Size: $DUMP_SIZE bytes ($(($DUMP_SIZE / 1024 / 1024)) MB)"
echo "================================================================================"
echo ""

# Check for repeating patterns
echo "1. PATTERN ANALYSIS"
echo "=================="
echo "First 256 bytes (hexdump):"
hexdump -C "$DUMP_FILE" | head -16
echo ""

# Check for repeating 8-byte pattern
PATTERN=$(head -c 8 "$DUMP_FILE" | hexdump -C | tail -1 | awk '{print $2$3$4$5$6$7$8$9}')
echo "First 8-byte pattern: $(head -c 8 "$DUMP_FILE" | hexdump -C | tail -1 | awk '{print $2$3$4$5$6$7$8$9}')"
echo ""

# Count pattern repetitions in first 1KB
PATTERN_COUNT=$(head -c 1024 "$DUMP_FILE" | grep -ao "$(head -c 8 "$DUMP_FILE" | od -An -tx1 | tr -d ' \n')" | wc -l)
echo "Pattern repetitions in first 1KB: $PATTERN_COUNT"
echo ""

# Check for ME firmware signatures
echo "2. ME FIRMWARE SIGNATURE SEARCH"
echo "==============================="
echo "Searching for known ME signatures..."

# ME header magic patterns
ME_MAGICS=(
    "\$ME"
    "MEFW"
    "\x24\x00\x00\x00"
    "\x01\x00\x00\x00"
)

for magic in "${ME_MAGICS[@]}"; do
    if grep -q -a "$magic" "$DUMP_FILE" 2>/dev/null; then
        OFFSET=$(grep -abo "$magic" "$DUMP_FILE" 2>/dev/null | head -1 | cut -d: -f1)
        echo "  ✓ Found '$magic' at offset 0x$(printf "%08X" $OFFSET)"
    fi
done
echo ""

# Check for version strings
echo "3. VERSION STRING SEARCH"
echo "======================="
VERSION_STRINGS=$(strings "$DUMP_FILE" | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -10)
if [ -n "$VERSION_STRINGS" ]; then
    echo "Found version-like strings:"
    echo "$VERSION_STRINGS" | sed 's/^/  /'
else
    echo "  No version strings found"
fi
echo ""

# Analyze entropy (compressed/encrypted data has high entropy)
echo "4. ENTROPY ANALYSIS"
echo "=================="
ENTROPY=$(python3 -c "
import sys
from collections import Counter

with open('$DUMP_FILE', 'rb') as f:
    data = f.read(10240)  # First 10KB
    
if len(data) == 0:
    print('  ERROR: Empty file')
    sys.exit(1)

# Calculate byte frequency
freq = Counter(data)
total = len(data)

# Calculate Shannon entropy
entropy = 0
for count in freq.values():
    p = count / total
    if p > 0:
        entropy -= p * (p.bit_length() - 1)

print(f'  Entropy (first 10KB): {entropy:.4f} bits/byte')
print(f'  Max entropy: 8.0 bits/byte (random data)')
print(f'  Min entropy: 0.0 bits/byte (repeating pattern)')

if entropy < 2.0:
    print('  → Low entropy: Likely structured data or repeating pattern')
elif entropy > 7.0:
    print('  → High entropy: Likely compressed or encrypted')
else:
    print('  → Medium entropy: Normal firmware data')
" 2>/dev/null || echo "  Python entropy calculation failed")
echo ""

# Check for SPI flash command patterns
echo "5. SPI FLASH COMMAND ANALYSIS"
echo "============================="
echo "First 8 bytes: $(head -c 8 "$DUMP_FILE" | hexdump -C | tail -1)"
echo ""
echo "Possible interpretations:"
echo "  03 00 A0 00 00 00 20 00"
echo ""
echo "  If this is SPI flash read data:"
echo "    - 0x03 = SPI Read command"
echo "    - 0x00A000 = Address (24-bit, little-endian) = 0xA00000"
echo "    - 0x000020 = Length (24-bit, little-endian) = 0x200000 (2MB)"
echo ""
echo "  If this is ME firmware structure:"
echo "    - Could be ME partition header"
echo "    - Could be ME module header"
echo "    - Pattern suggests structured data"
echo ""

# Check middle and end of file
echo "6. FILE STRUCTURE (MIDDLE & END)"
echo "==============================="
MIDDLE_OFFSET=$(($DUMP_SIZE / 2))
END_OFFSET=$(($DUMP_SIZE - 256))

echo "Middle of file (offset 0x$(printf "%08X" $MIDDLE_OFFSET)):"
dd if="$DUMP_FILE" bs=1 skip=$MIDDLE_OFFSET count=64 2>/dev/null | hexdump -C | head -4
echo ""

echo "End of file (last 64 bytes):"
tail -c 64 "$DUMP_FILE" | hexdump -C
echo ""

# Check for non-zero regions
echo "7. NON-ZERO REGION ANALYSIS"
echo "==========================="
echo "Checking for non-zero data regions..."
NONZERO_START=$(od -An -td1 "$DUMP_FILE" | awk '{for(i=1;i<=NF;i++) if($i!=0) {print NR*16+(i-1); exit}}' | head -1)
NONZERO_COUNT=$(od -An -td1 "$DUMP_FILE" | awk '{for(i=1;i<=NF;i++) if($i!=0) count++} END {print count+0}')

echo "  First non-zero byte at offset: $NONZERO_START"
echo "  Total non-zero bytes: $NONZERO_COUNT / $DUMP_SIZE ($(($NONZERO_COUNT * 100 / $DUMP_SIZE))%)"
echo ""

# Compare with expected ME region
echo "8. ME REGION COMPARISON"
echo "======================"
ME_REGION_SIZE=$((0x00EC7FFF - 0x00126000 + 1))
echo "Expected ME region size: $ME_REGION_SIZE bytes ($(($ME_REGION_SIZE / 1024 / 1024)) MB)"
echo "Dump file size: $DUMP_SIZE bytes ($(($DUMP_SIZE / 1024 / 1024)) MB)"
if [ "$DUMP_SIZE" -eq "$ME_REGION_SIZE" ]; then
    echo "  ✓ Size matches expected ME region"
elif [ "$DUMP_SIZE" -gt "$ME_REGION_SIZE" ]; then
    echo "  ⚠ Dump is larger than ME region (may include padding or extra data)"
else
    echo "  ⚠ Dump is smaller than ME region (may be partial dump)"
fi
echo ""

# Final assessment
echo "================================================================================"
echo "STRUCTURE ASSESSMENT"
echo "================================================================================"
echo ""
if [ "$PATTERN_COUNT" -gt 100 ]; then
    echo "⚠️  WARNING: Highly repetitive pattern detected"
    echo "   This may indicate:"
    echo "   - SPI flash read command data (not actual ME firmware)"
    echo "   - Dump method captured SPI commands instead of firmware"
    echo "   - ME firmware is encrypted/compressed and appears random"
    echo ""
fi

if [ -z "$VERSION_STRINGS" ]; then
    echo "⚠️  WARNING: No ME version strings found"
    echo "   This may indicate:"
    echo "   - Dump is not valid ME firmware"
    echo "   - ME firmware is encrypted/compressed"
    echo "   - Dump contains raw SPI data, not parsed ME firmware"
    echo ""
fi

echo "Recommendations:"
echo "  1. Verify dump was created with correct tool (flashrom, Intel FIT, etc.)"
echo "  2. Check if dump method captured SPI commands vs. actual firmware"
echo "  3. Compare with known-good ME firmware dumps from same platform"
echo "  4. If pattern is SPI commands, may need to parse/extract actual firmware"
echo ""
echo "================================================================================"
