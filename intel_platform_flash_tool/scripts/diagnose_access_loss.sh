#!/bin/bash
#
# Access Loss Diagnosis Script
# Investigates why access was reduced
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}✓${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*"
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

echo "================================================================================"
echo "ACCESS LOSS DIAGNOSIS"
echo "================================================================================"
echo "Investigating why access was reduced..."
echo "================================================================================"
echo ""

# 1. Check HAP Status
echo "1. HAP MODE STATUS"
echo "=================="
HFSTS1_SYSFS=$(cat /sys/class/mei/mei0/fw_status 2>/dev/null || echo "")
if [ -n "$HFSTS1_SYSFS" ]; then
    HFSTS1_DEC=$((0x$HFSTS1_SYSFS))
    HAP_BIT=$(( (HFSTS1_DEC >> 12) & 1 ))
    echo "HFSTS1: 0x$HFSTS1_SYSFS"
    echo "HAP bit (12): $HAP_BIT"
    if [ "$HAP_BIT" -eq 0 ]; then
        error "HAP MODE: DISABLED (but sticker/doorbell present - MISMATCH!)"
    else
        log "HAP MODE: ENABLED"
    fi
else
    warn "Could not read HFSTS1"
fi
echo ""

# 2. Check ME Firmware Version
echo "2. ME FIRMWARE VERSION"
echo "======================"
ME_VERSION=$(cat /sys/class/mei/mei0/fw_ver 2>/dev/null || echo "")
if [ -n "$ME_VERSION" ]; then
    echo "ME Version: $ME_VERSION"
    warn "Current: 0:18.0.18.2571"
    warn "This is a recent version - may have stricter security"
else
    warn "ME version not available"
fi
echo ""

# 3. Check Unlock Module Status
echo "3. UNLOCK MODULE STATUS"
echo "======================="
if [ -f /proc/dsmil_unlock/status ]; then
    cat /proc/dsmil_unlock/status
else
    warn "Unlock status not available"
fi
echo ""

# 4. Check CPU Features
echo "4. CPU FEATURES (AVX512/AMX)"
echo "============================="
if lscpu | grep -qi "avx512\|amx"; then
    log "AVX512/AMX visible in CPU flags"
    lscpu | grep -i "avx512\|amx"
else
    error "AVX512/AMX NOT visible in CPU flags"
    warn "Features may be hidden/disabled"
fi
echo ""

# 5. Check MSR Access
echo "5. MSR ACCESS"
echo "============="
if sudo rdmsr 0x1A0 2>/dev/null >/dev/null; then
    log "MSR access: Available"
else
    error "MSR access: RESTRICTED"
    warn "Cannot read MSRs directly"
fi
echo ""

# 6. Check BIOS Tokens
echo "6. BIOS TOKENS"
echo "=============="
if command -v cctk-milspec >/dev/null 2>&1; then
    MANUF_MODE=$(sudo cctk-milspec --token 0x1041 2>/dev/null | grep -i "value" || echo "")
    DEBUG_MODE=$(sudo cctk-milspec --token 0x1042 2>/dev/null | grep -i "value" || echo "")
    if [ -n "$MANUF_MODE" ]; then
        echo "Manufacturing Mode: $MANUF_MODE"
    fi
    if [ -n "$DEBUG_MODE" ]; then
        echo "Debug Mode: $DEBUG_MODE"
    fi
else
    warn "CCTK not available"
fi
echo ""

# 7. Check for Recent Changes
echo "7. RECENT SYSTEM CHANGES"
echo "========================"
echo "Checking for ME/BIOS updates..."
if [ -f /var/log/dpkg.log ]; then
    echo "Recent package updates:"
    grep -i "firmware\|microcode\|intel" /var/log/dpkg.log | tail -5 || echo "  None found"
fi
echo ""

# 8. Summary
echo "================================================================================"
echo "DIAGNOSIS SUMMARY"
echo "================================================================================"
echo ""
if [ "${HAP_BIT:-0}" -eq 0 ]; then
    error "CRITICAL: HAP MODE IS DISABLED"
    echo ""
    echo "Evidence of access loss:"
    echo "  - HAP sticker/doorbell present (physical evidence of HAP capability)"
    echo "  - BUT HAP bit (12) = 0 (HAP mode disabled)"
    echo "  - This indicates HAP mode was previously enabled but is now disabled"
    echo ""
    echo "Most likely causes:"
    echo "  1. ME firmware auto-update reset HAP mode"
    echo "  2. BIOS/UEFI update tightened security"
    echo "  3. ME security policy reset"
    echo "  4. Cold boot reset HAP state"
    echo ""
    echo "Recovery steps:"
    echo "  1. Re-activate HAP mode:"
    echo "     sudo insmod hap_device255_me_tpm_coordinated.ko run_stage=25"
    echo ""
    echo "  2. Re-run full unlock sequence:"
    echo "     sudo insmod unlock_coordination.ko"
    echo "     sudo insmod device255_unlock.ko"
    echo "     sudo insmod hap_device255_me_tpm_coordinated.ko autorun_all=1"
    echo ""
    echo "  3. Use UEFI script for persistent activation:"
    echo "     Copy uefi_unlock_maximum_aggressive.nsh to EFI shell as uefi.nsh"
    echo ""
fi
echo "================================================================================"
