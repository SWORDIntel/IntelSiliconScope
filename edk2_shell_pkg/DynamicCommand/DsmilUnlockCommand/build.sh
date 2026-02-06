#!/bin/bash
#
# Build DsmilUnlockCommand after initialization
# Run init_build_system.sh first if this is the first time
#

set -e

EDK2_ROOT="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"

if [ ! -d "$EDK2_ROOT" ]; then
    echo "ERROR: EDK2 root not found at $EDK2_ROOT"
    exit 1
fi

cd "$EDK2_ROOT"

# Set up environment (same as init script)
export WORKSPACE="$EDK2_ROOT"
export PACKAGES_PATH="$WORKSPACE"
export EDK_TOOLS_PATH="$WORKSPACE/BaseTools"
export PYTHON_COMMAND=python3
export PYTHONHASHSEED=1
export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"
export PYTHONPATH="$WORKSPACE/BaseTools/Source/Python${PYTHONPATH:+:$PYTHONPATH}"

echo "================================================================================"
echo "Building DSMIL Unlock Dynamic Command"
echo "================================================================================"
echo "WORKSPACE: $WORKSPACE"
echo "Module: ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf"
echo "================================================================================"
echo ""

# Build the module
"$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" \
    -p ShellPkg/ShellPkg.dsc \
    -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \
    -a X64 \
    -t GCC5 \
    -b RELEASE

BUILD_OUTPUT="$WORKSPACE/Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi"

if [ -f "$BUILD_OUTPUT" ]; then
    echo ""
    echo "================================================================================"
    echo "✓ Build successful!"
    echo "================================================================================"
    echo "Output: $BUILD_OUTPUT"
    ls -lh "$BUILD_OUTPUT"
    echo ""
    echo "To install to EFI partition:"
    echo "  sudo cp $BUILD_OUTPUT /mnt/sdb1/EFI/BOOT/"
    echo ""
    echo "To use in UEFI shell:"
    echo "  Shell> load DsmilUnlockDynamicCommand.efi"
    echo "  Shell> dsmil-unlock full aggressive"
    echo "================================================================================"
    exit 0
else
    echo ""
    echo "================================================================================"
    echo "✗ Build failed - output not found"
    echo "================================================================================"
    echo "Expected: $BUILD_OUTPUT"
    echo ""
    echo "Check build logs in: $WORKSPACE/Build/Shell/RELEASE_GCC5/X64/"
    if [ -d "$WORKSPACE/Build/Shell/RELEASE_GCC5/X64" ]; then
        echo ""
        echo "Build directory contents:"
        ls -la "$WORKSPACE/Build/Shell/RELEASE_GCC5/X64/" | head -20
    fi
    exit 1
fi
