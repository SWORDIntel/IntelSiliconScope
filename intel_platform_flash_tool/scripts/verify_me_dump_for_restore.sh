#!/bin/bash
# ME Dump Verification for Restoration
# Verifies that an ME dump is valid and safe to restore

DUMP_FILE="${1:-docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin}"

if [ ! -f "$DUMP_FILE" ]; then
    echo "ERROR: ME dump file not found: $DUMP_FILE"
    exit 1
fi

DUMP_SIZE=$(stat -c%s "$DUMP_FILE")
ME_REGION_SIZE=$((0x00EC7FFF - 0x00126000 + 1))

echo "================================================================================"
echo "ME DUMP VERIFICATION FOR RESTORATION"
echo "================================================================================"
echo "File: $DUMP_FILE"
echo "Size: $DUMP_SIZE bytes ($(($DUMP_SIZE / 1024 / 1024)) MB)"
echo "Expected ME Region: $ME_REGION_SIZE bytes ($(($ME_REGION_SIZE / 1024 / 1024)) MB)"
echo "================================================================================"
echo ""

# Check 1: File size
echo "1. SIZE VERIFICATION"
echo "==================="
if [ "$DUMP_SIZE" -eq "$ME_REGION_SIZE" ]; then
    echo "  ✓ Size matches expected ME region exactly"
    SIZE_OK=1
elif [ "$DUMP_SIZE" -gt "$ME_REGION_SIZE" ]; then
    DIFF=$(($DUMP_SIZE - $ME_REGION_SIZE))
    echo "  ⚠ Dump is $DIFF bytes larger than ME region"
    echo "     May include padding or extra data"
    SIZE_OK=1
else
    echo "  ✗ Dump is smaller than expected ME region"
    echo "     May be incomplete"
    SIZE_OK=0
fi
echo ""

# Check 2: Non-zero data
echo "2. DATA INTEGRITY"
echo "================="
NONZERO_COUNT=$(od -An -td1 "$DUMP_FILE" | awk '{for(i=1;i<=NF;i++) if($i!=0) count++} END {print count+0}')
NONZERO_PERCENT=$((NONZERO_COUNT * 100 / $DUMP_SIZE))
echo "  Non-zero bytes: $NONZERO_COUNT / $DUMP_SIZE ($NONZERO_PERCENT%)"

if [ "$NONZERO_PERCENT" -lt 10 ]; then
    echo "  ✗ Too few non-zero bytes - dump may be invalid"
    DATA_OK=0
elif [ "$NONZERO_PERCENT" -gt 90 ]; then
    echo "  ✓ High data density - looks like valid firmware"
    DATA_OK=1
else
    echo "  ⚠ Moderate data density - may be valid but sparse"
    DATA_OK=1
fi
echo ""

# Check 3: Pattern analysis
echo "3. PATTERN ANALYSIS"
echo "=================="
FIRST_8=$(head -c 8 "$DUMP_FILE" | hexdump -C | tail -1 | awk '{print $2$3$4$5$6$7$8$9}')
echo "  First 8 bytes: $(head -c 8 "$DUMP_FILE" | hexdump -C | tail -1 | awk '{for(i=2;i<=9;i++) printf "%s ", $i}')"

# Check if pattern repeats excessively (might be SPI commands, not firmware)
PATTERN_REPEATS=$(head -c 1024 "$DUMP_FILE" | grep -ao "$(head -c 8 "$DUMP_FILE" | od -An -tx1 | tr -d ' \n')" | wc -l)
if [ "$PATTERN_REPEATS" -gt 100 ]; then
    echo "  ⚠ Highly repetitive pattern detected ($PATTERN_REPEATS repetitions in first 1KB)"
    echo "     This may indicate:"
    echo "     - SPI flash command data (not actual firmware)"
    echo "     - Structured ME firmware with repeating headers"
    echo "     - Dump method captured commands instead of data"
    PATTERN_OK=0
else
    echo "  ✓ Pattern appears normal (not excessively repetitive)"
    PATTERN_OK=1
fi
echo ""

# Check 4: ME signatures
echo "4. ME FIRMWARE SIGNATURES"
echo "========================"
ME_SIGS_FOUND=0
for sig in "\$ME" "MEFW" "MEIF"; do
    if grep -q -a "$sig" "$DUMP_FILE" 2>/dev/null; then
        OFFSET=$(grep -abo "$sig" "$DUMP_FILE" 2>/dev/null | head -1 | cut -d: -f1)
        echo "  ✓ Found '$sig' signature at offset 0x$(printf "%08X" $OFFSET)"
        ME_SIGS_FOUND=$((ME_SIGS_FOUND + 1))
    fi
done

if [ "$ME_SIGS_FOUND" -eq 0 ]; then
    echo "  ⚠ No ME firmware signatures found"
    echo "     This may indicate:"
    echo "     - ME firmware is encrypted/compressed"
    echo "     - Dump contains raw SPI data, not parsed firmware"
    echo "     - ME firmware structure is different than expected"
    SIG_OK=0
else
    echo "  ✓ Found $ME_SIGS_FOUND ME signature(s)"
    SIG_OK=1
fi
echo ""

# Check 5: Version strings
echo "5. VERSION INFORMATION"
echo "====================="
VERSION_STRINGS=$(strings "$DUMP_FILE" | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -5)
if [ -n "$VERSION_STRINGS" ]; then
    echo "  ✓ Found version-like strings:"
    echo "$VERSION_STRINGS" | sed 's/^/    /'
    VERSION_OK=1
else
    echo "  ⚠ No version strings found"
    VERSION_OK=0
fi
echo ""

# Check 6: End of file (should have valid data)
echo "6. END-OF-FILE ANALYSIS"
echo "====================="
LAST_1KB=$(tail -c 1024 "$DUMP_FILE" | hexdump -C | head -5)
LAST_NONZERO=$(tail -c 1024 "$DUMP_FILE" | tr -d '\0' | wc -c)
echo "  Last 1KB non-zero bytes: $LAST_NONZERO / 1024"

if [ "$LAST_NONZERO" -lt 100 ]; then
    echo "  ⚠ End of file is mostly zeros"
    END_OK=0
else
    echo "  ✓ End of file contains valid data"
    END_OK=1
fi
echo ""

# Check 7: Compare with current ME version
echo "7. ME VERSION COMPARISON"
echo "========================"
CURRENT_ME_VERSION=$(cat /sys/class/mei/mei0/me_fw_version 2>/dev/null || echo "unknown")
echo "  Current ME version: $CURRENT_ME_VERSION"
echo "  Expected ME version: 0:18.0.18.2571 (from dump metadata)"
echo "  ⚠ Version check: Ensure dump matches current system"
echo ""

# Check 8: Source verification
echo "8. SOURCE VERIFICATION"
echo "====================="
echo "  Dump source: LAT5150DRVMIL repository (older system state)"
echo "  Dump method: DSMIL kernel module sysfs interface"
echo "  Dump date: December 26, 2025 (from README)"
echo "  ⚠ Verify this dump came from THIS EXACT SYSTEM"
echo ""

# Final assessment
echo "================================================================================"
echo "VERIFICATION SUMMARY"
echo "================================================================================"
echo ""

SCORE=0
TOTAL=7

[ "$SIZE_OK" = "1" ] && SCORE=$((SCORE + 1)) || echo "  ✗ Size check failed"
[ "$DATA_OK" = "1" ] && SCORE=$((SCORE + 1)) || echo "  ✗ Data integrity check failed"
[ "$PATTERN_OK" = "1" ] && SCORE=$((SCORE + 1)) || echo "  ✗ Pattern check failed"
[ "$SIG_OK" = "1" ] && SCORE=$((SCORE + 1)) || echo "  ✗ Signature check failed"
[ "$VERSION_OK" = "1" ] && SCORE=$((SCORE + 1)) || echo "  ✗ Version check failed"
[ "$END_OK" = "1" ] && SCORE=$((SCORE + 1)) || echo "  ✗ End-of-file check failed"

echo "Verification Score: $SCORE / $TOTAL"
echo ""

if [ "$SCORE" -ge 5 ]; then
    echo "✓ VERIFICATION PASSED"
    echo ""
    echo "The dump appears to be valid ME firmware and may be safe to restore."
    echo ""
    echo "⚠️  CRITICAL WARNINGS:"
    echo "  1. Ensure this dump came from THIS EXACT SYSTEM"
    echo "  2. Ensure ME version matches (0:18.0.18.2571)"
    echo "  3. Backup current flash before restoration"
    echo "  4. System must be on AC power (not battery)"
    echo "  5. Restoration can BRICK the system if dump is incorrect"
    echo ""
    echo "Next step: Run restore_me_firmware.sh with this dump file"
    EXIT_CODE=0
elif [ "$SCORE" -ge 3 ]; then
    echo "⚠️  VERIFICATION PARTIAL"
    echo ""
    echo "The dump has some issues but may still be restorable."
    echo "Review the failed checks above before proceeding."
    echo ""
    echo "⚠️  HIGH RISK: Proceed with extreme caution"
    EXIT_CODE=1
else
    echo "✗ VERIFICATION FAILED"
    echo ""
    echo "The dump appears to be invalid or unsafe for restoration."
    echo "Do NOT restore this dump without further investigation."
    EXIT_CODE=2
fi

echo "================================================================================"
exit $EXIT_CODE
