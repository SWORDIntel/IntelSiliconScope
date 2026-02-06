#!/bin/bash
set -e

# ME Firmware Restoration using Intel Tools
# Attempts to use Intel Platform Flash Tool or Intel FIT to bypass ME protection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_DUMP="${SCRIPT_DIR}/../../docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin"

echo "================================================================================"
echo "ME FIRMWARE RESTORATION USING INTEL TOOLS"
echo "================================================================================"
echo "This script attempts to use Intel tools to bypass ME protection"
echo "and restore ME firmware from dump."
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
echo "Size: $(stat -c%s "$ME_DUMP") bytes"
echo ""

# Check for Intel Platform Flash Tool
INTEL_TOOL_DIR="${SCRIPT_DIR}/platformflashtoollite_extracted"
FLS_TOOL="${INTEL_TOOL_DIR}/opt/intel/platformflashtoollite/bin/flsTool"
PLATFORM_TOOL="${INTEL_TOOL_DIR}/opt/intel/platformflashtoollite/bin/platformflashtoollite"

echo "=== Checking Intel Tools ==="
if [ -f "$FLS_TOOL" ]; then
    echo "✓ flsTool found: $FLS_TOOL"
    file "$FLS_TOOL"
else
    echo "✗ flsTool not found"
fi

if [ -f "$PLATFORM_TOOL" ]; then
    echo "✓ platformflashtoollite found: $PLATFORM_TOOL"
    file "$PLATFORM_TOOL"
else
    echo "✗ platformflashtoollite not found"
fi
echo ""

# Check for Intel FIT (Flash Image Tool)
echo "=== Checking for Intel FIT ==="
echo "Intel FIT (Flash Image Tool) is the proper tool for ME firmware manipulation"
echo "It's typically a Windows tool, but may have Linux alternatives"
echo ""

# Check if we can download Intel FIT
echo "Intel FIT Download Options:"
echo "  1. Official Intel site (requires registration)"
echo "  2. May be available in Intel ME System Tools"
echo "  3. May require Windows environment or Wine"
echo ""

# Alternative: Try using kernel module to write ME region directly
echo "=== Alternative: Kernel Module Direct Write ==="
echo "We have kernel modules that can access SPI flash directly"
echo "This may bypass ME protection if HAP mode can be activated first"
echo ""

KERNEL_MODULE="${SCRIPT_DIR}/../../scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.ko"
if [ -f "$KERNEL_MODULE" ]; then
    echo "✓ Kernel module found: $KERNEL_MODULE"
    echo ""
    echo "Option: Load kernel module and use SPI flash write capability"
    echo "  This requires:"
    echo "    1. HAP mode activation (may be in the module)"
    echo "    2. SPI controller access"
    echo "    3. Direct flash write capability"
    echo ""
    read -p "Attempt kernel module approach? (yes/no): " USE_MODULE
    
    if [ "$USE_MODULE" = "yes" ]; then
        echo ""
        echo "=== Loading Kernel Module for SPI Flash Write ==="
        echo "⚠️  This is experimental and may not work"
        echo ""
        
        # Check if module is already loaded
        if lsmod | grep -q "hap_device255"; then
            echo "Module already loaded, removing first..."
            sudo rmmod hap_device255_me_tpm_coordinated 2>/dev/null || true
        fi
        
        # Load module
        echo "Loading module..."
        if sudo insmod "$KERNEL_MODULE" 2>&1 | tee /tmp/module_load.log; then
            echo "✓ Module loaded"
            echo ""
            echo "Checking for SPI flash write capability..."
            echo "Note: The module may need to be enhanced with SPI write functionality"
            echo ""
            echo "Current module capabilities:"
            dmesg | tail -20 | grep -i "spi\|flash\|me" || echo "No relevant messages"
        else
            echo "✗ Failed to load module"
            echo "Check /tmp/module_load.log for details"
            exit 1
        fi
    fi
else
    echo "✗ Kernel module not found: $KERNEL_MODULE"
fi

echo ""
echo "================================================================================"
echo "RECOMMENDATION"
echo "================================================================================"
echo ""
echo "Intel Platform Flash Tool Lite is primarily for flashing pre-prepared"
echo "firmware images, not for direct ME region manipulation."
echo ""
echo "For ME firmware restoration, you need:"
echo "  1. Intel FIT (Flash Image Tool) - Windows tool, may work with Wine"
echo "  2. External SPI programmer (hardware access)"
echo "  3. ME in HAP mode (disabled) - then flashrom can write"
echo ""
echo "Current situation:"
echo "  - ME is active and protecting ME region (read-only)"
echo "  - flashrom cannot write to ME region while ME is active"
echo "  - We're trying to restore ME firmware to enable HAP mode"
echo "  - This is a catch-22 situation"
echo ""
echo "Next steps:"
echo "  1. Download Intel FIT from Intel (may require registration)"
echo "  2. Or use external SPI programmer to write ME region"
echo "  3. Or investigate if kernel module can disable ME temporarily"
echo ""
echo "================================================================================"
