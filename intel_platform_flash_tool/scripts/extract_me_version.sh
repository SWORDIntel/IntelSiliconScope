#!/bin/bash
# Extract ME Version from ME Dump
# Searches for ME firmware version information in dump files

ME_DUMP="${1:-docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin}"

if [ ! -f "$ME_DUMP" ]; then
    echo "ERROR: ME dump file not found: $ME_DUMP"
    exit 1
fi

echo "================================================================================"
echo "ME VERSION EXTRACTION FROM DUMP"
echo "================================================================================"
echo "File: $ME_DUMP"
echo "Size: $(stat -c%s "$ME_DUMP") bytes"
echo "================================================================================"
echo ""

# Method 1: Search for version strings
echo "1. VERSION STRING SEARCH"
echo "========================"
VERSION_STRINGS=$(strings "$ME_DUMP" | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort -u)
if [ -n "$VERSION_STRINGS" ]; then
    echo "Found version-like strings:"
    echo "$VERSION_STRINGS" | sed 's/^/  /'
else
    echo "  No version strings found"
fi
echo ""

# Method 2: Search for ME-specific version patterns
echo "2. ME-SPECIFIC VERSION PATTERNS"
echo "==============================="
ME_PATTERNS=$(strings "$ME_DUMP" | grep -iE "version|v[0-9]|me[0-9]|18\.|0:18|MEIF|MEFW" | head -20)
if [ -n "$ME_PATTERNS" ]; then
    echo "Found ME-related strings:"
    echo "$ME_PATTERNS" | sed 's/^/  /'
else
    echo "  No ME-specific patterns found"
fi
echo ""

# Method 3: Search for HFSTS1 register value
echo "3. HFSTS1 REGISTER SEARCH"
echo "========================="
echo "HFSTS1 (ME Firmware Status 1) contains version and HAP bit"
echo "Expected format: 32-bit little-endian"
echo "  Current (HAP disabled): 0x94000245 = 45 02 00 94"
echo "  HAP enabled:             0x94001245 = 45 12 00 94"
echo ""

HFSTS1_PATTERNS=$(hexdump -C "$ME_DUMP" | grep -E "45 02 00 94|45 12 00 94|94 00 02 45|94 00 12 45")
if [ -n "$HFSTS1_PATTERNS" ]; then
    echo "Found HFSTS1-like patterns:"
    echo "$HFSTS1_PATTERNS" | head -5 | sed 's/^/  /'
    
    # Count occurrences
    HAP_DISABLED=$(echo "$HFSTS1_PATTERNS" | grep -c "45 02 00 94\|94 00 02 45" || echo "0")
    HAP_ENABLED=$(echo "$HFSTS1_PATTERNS" | grep -c "45 12 00 94\|94 00 12 45" || echo "0")
    echo ""
    echo "  HAP disabled pattern (0x94000245): $HAP_DISABLED occurrences"
    echo "  HAP enabled pattern (0x94001245): $HAP_ENABLED occurrences"
else
    echo "  No HFSTS1 patterns found"
fi
echo ""

# Method 4: Search for ME header structures
echo "4. ME HEADER STRUCTURE SEARCH"
echo "============================="
echo "Searching for ME firmware header signatures..."
ME_HEADERS=$(hexdump -C "$ME_DUMP" | grep -E "\$ME|MEFW|MEIF|24 00 00 00" | head -5)
if [ -n "$ME_HEADERS" ]; then
    echo "Found potential ME headers:"
    echo "$ME_HEADERS" | sed 's/^/  /'
else
    echo "  No ME header signatures found"
fi
echo ""

# Method 5: Analyze first 1KB for version info
echo "5. HEADER REGION ANALYSIS"
echo "========================="
echo "First 256 bytes (potential header region):"
hexdump -C "$ME_DUMP" | head -16
echo ""

# Method 6: Check current system ME version for comparison
echo "6. CURRENT SYSTEM ME VERSION"
echo "============================"
if [ -f /sys/class/mei/mei0/me_fw_version ]; then
    CURRENT_VERSION=$(cat /sys/class/mei/mei0/me_fw_version)
    echo "  Current ME version: $CURRENT_VERSION"
    echo ""
    echo "  Expected from dump metadata: 0:18.0.18.2571"
    if echo "$CURRENT_VERSION" | grep -q "18.0.18.2571"; then
        echo "  ✓ Version matches expected"
    else
        echo "  ⚠ Version does not match expected"
    fi
else
    echo "  ME version sysfs not available"
    echo "  Try: cat /sys/class/mei/mei0/me_fw_version"
fi
echo ""

# Summary
echo "================================================================================"
echo "SUMMARY"
echo "================================================================================"
echo ""
echo "ME Version Extraction Methods:"
echo "  1. Version strings: $(echo "$VERSION_STRINGS" | wc -l) found"
echo "  2. ME patterns: $(echo "$ME_PATTERNS" | wc -l) found"
echo "  3. HFSTS1 patterns: $(echo "$HFSTS1_PATTERNS" | wc -l) found"
echo ""
echo "Note: ME firmware may be encrypted/compressed, making version extraction"
echo "      difficult. The dump may need to be analyzed with specialized tools"
echo "      (Intel FIT, MEConfig) for accurate version information."
echo ""
echo "================================================================================"
