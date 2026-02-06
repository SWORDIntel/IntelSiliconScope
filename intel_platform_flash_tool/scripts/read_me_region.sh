#!/bin/bash
#
# Read ME Firmware Region (FREG2) via SPI Controller
# Uses devmem2 to access SPI controller MMIO directly
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVMEM2="${SCRIPT_DIR}/../devmem2/devmem2"
OUTPUT_FILE="${1:-/tmp/me_freg2_direct.bin}"

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
echo "ME FIRMWARE REGION (FREG2) READER"
echo "================================================================================"
echo "ME Region: 0x00126000-0x00EC7FFF (~14.5MB)"
echo "Output: $OUTPUT_FILE"
echo "================================================================================"
echo ""

# Check devmem2
if [ ! -f "$DEVMEM2" ]; then
    error "devmem2 not found at $DEVMEM2"
    exit 1
fi

# SPI Controller MMIO Base
SPI_MMIO_BASE="0x7c120000"

# ME Region boundaries (from flashrom)
ME_START="0x00126000"
ME_END="0x00EC7FFF"
ME_SIZE=$((0x00EC7FFF - 0x00126000 + 1))

info "ME Region Start: $ME_START"
info "ME Region End: $ME_END"
info "ME Region Size: $ME_SIZE bytes ($(($ME_SIZE / 1024 / 1024)) MB)"
echo ""

warn "NOTE: Direct SPI flash read via MMIO is complex."
warn "Intel SPI controllers use hardware sequencing."
warn "This script attempts basic read operations."
echo ""

# Read SPI controller registers
info "Reading SPI controller registers..."
SPI_STATUS=$(sudo "$DEVMEM2" "$SPI_MMIO_BASE" 2>/dev/null | grep -oP '0x[0-9a-fA-F]+' | head -1 || echo "0x0")
log "SPI Status: $SPI_STATUS"

# Note: Direct SPI flash reading requires hardware sequencing
# which is complex to implement via devmem2
warn "Direct SPI flash read via devmem2 is not fully implemented."
warn "Use kernel module Stage 5 for SPI controller register access."
warn "Or use specialized tools (Intel Flash Image Tool, MEConfig)."
echo ""

info "Alternative: Use kernel module to read SPI registers:"
info "  sudo insmod hap_device255_me_tpm_coordinated.ko run_stage=5"
info "  Check /tmp/me_firmware_dump.bin for region info"
echo ""

error "Cannot read ME region directly via devmem2 (requires hardware sequencing)"
error "ME region is read-only and may be protected by active ME"
exit 1
