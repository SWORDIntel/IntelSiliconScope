#!/bin/bash
set -e

# ME Firmware Restoration using Kernel Module SPI Write
# Uses the hap_device255_me_tpm_coordinated.ko module's Stage 6
# to write ME firmware directly to SPI flash via hardware sequencing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_DUMP="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin"
MODULE_PATH="${SCRIPT_DIR}/../../scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.ko"

echo "================================================================================"
echo "ME FIRMWARE RESTORATION VIA KERNEL MODULE"
echo "================================================================================"
echo "This script uses the kernel module's SPI flash write capability"
echo "to restore ME firmware directly to SPI flash."
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

echo "ME Dump: $ME_DUMP"
echo "Size: $(stat -c%s "${ME_DUMP}") bytes"
echo ""

# Check module
if [ ! -f "$MODULE_PATH" ]; then
    echo "ERROR: Module not found: $MODULE_PATH"
    echo "Please build the module first:"
    echo "  cd scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module"
    echo "  make"
    exit 1
fi

echo "Module: $MODULE_PATH"
echo ""

# Check if module is already loaded
if lsmod | grep -q "hap_device255_me_tpm_coordinated"; then
    echo "⚠️  Module is already loaded"
    echo "Unloading existing module..."
    rmmod hap_device255_me_tpm_coordinated || true
    sleep 1
fi

echo "================================================================================"
echo "LOADING MODULE WITH STAGE 6 (ME FIRMWARE WRITE)"
echo "================================================================================"
echo "⚠️⚠⚠ CRITICAL: This will WRITE to SPI flash! ⚠⚠⚠"
echo "⚠️⚠⚠ This can BRICK the system if incorrect! ⚠⚠⚠"
echo ""
read -p "Are you absolutely sure you want to proceed? (type 'YES' to continue): " confirm
if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Loading module with Stage 2.5 (HAP activation) first, then Stage 6 (ME write)..."
echo "  Module: $MODULE_PATH"
echo "  ME Dump: $ME_DUMP"
echo ""
echo "Step 1: Activating HAP mode (may disable ME write protection)..."
echo ""

# Step 1: Load module with Stage 2.5 (HAP activation) first
if insmod "$MODULE_PATH" run_stage=25 me_dump_path="$ME_DUMP" 2>&1 | tee /tmp/me_hap_activation.log; then
    echo ""
    echo "Step 1 completed. Checking HAP mode status..."
    dmesg | tail -20 | grep -E "HAP|Stage 2.5" || true
    echo ""
    sleep 2
    
    # Unload and reload for Stage 6
    echo "Unloading module for Stage 6..."
    rmmod hap_device255_me_tpm_coordinated || true
    sleep 1
    echo ""
fi

echo "Step 2: Writing ME firmware to SPI flash..."
echo ""

# Step 2: Load module with Stage 6 (ME firmware write)
if insmod "$MODULE_PATH" run_stage=6 me_dump_path="$ME_DUMP" 2>&1 | tee /tmp/me_write_module.log; then
    echo ""
    echo "================================================================================"
    echo "✓ MODULE LOADED - CHECKING RESULTS"
    echo "================================================================================"
    
    # Check dmesg for results
    echo "Recent kernel messages:"
    dmesg | tail -50 | grep -E "MAX-POTENCY|ME Write|SPI|Stage 6" || true
    
    echo ""
    echo "================================================================================"
    if dmesg | tail -100 | grep -q "Stage 6 completed - ME firmware written"; then
        echo "✓✓✓ ME FIRMWARE RESTORATION COMPLETE"
        echo "================================================================================"
        echo "⚠️  REBOOT REQUIRED for changes to take effect"
        echo ""
        echo "After reboot, check HAP mode:"
        echo "  sudo devmem2 0x50192DD040"
        echo "  (HAP bit should be set: bit 12 = 1)"
    else
        echo "⚠️  CHECK RESULTS ABOVE"
        echo "================================================================================"
        echo "Review /tmp/me_write_module.log and dmesg for details"
    fi
else
    echo ""
    echo "================================================================================"
    echo "✗ MODULE LOAD FAILED"
    echo "================================================================================"
    echo "Check /tmp/me_write_module.log and dmesg for errors"
    exit 1
fi
