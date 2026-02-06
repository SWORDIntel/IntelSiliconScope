#!/bin/bash
#
# Complete EDK2 Build using edksetup.sh
# This sources edksetup.sh and builds the module
#

set -e

EDK2_ROOT="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"

if [ ! -d "$EDK2_ROOT" ]; then
    echo "ERROR: EDK2 root not found"
    exit 1
fi

cd "$EDK2_ROOT"

echo "================================================================================"
echo "EDK2 Complete Build - DsmilUnlockCommand"
echo "================================================================================"
echo ""

# Source edksetup.sh to set up environment
echo "[1] Sourcing edksetup.sh..."
source edksetup.sh >/dev/null 2>&1 || {
    # If sourcing fails, set up manually
    export WORKSPACE="$EDK2_ROOT"
    export PACKAGES_PATH="$WORKSPACE"
    export EDK_TOOLS_PATH="$WORKSPACE/BaseTools"
    export PYTHON_COMMAND=python3
    export PYTHONHASHSEED=1
    export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"
    if [ -f "$WORKSPACE/BaseTools/BuildEnv" ]; then
        . "$WORKSPACE/BaseTools/BuildEnv"
    fi
}

echo "  WORKSPACE: $WORKSPACE"
echo "  PACKAGES_PATH: $PACKAGES_PATH"
echo ""

# Build the module
echo "[2] Building module..."
build -p ShellPkg/ShellPkg.dsc \
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
    echo "To install:"
    echo "  sudo cp $BUILD_OUTPUT /mnt/sdb1/EFI/BOOT/"
    echo "================================================================================"
    exit 0
else
    echo ""
    echo "================================================================================"
    echo "✗ Build failed - output not found"
    echo "================================================================================"
    if [ -d "$WORKSPACE/Build/Shell/RELEASE_GCC5/X64" ]; then
        echo "Build directory contents:"
        ls -la "$WORKSPACE/Build/Shell/RELEASE_GCC5/X64/" | head -20
    fi
    exit 1
fi
