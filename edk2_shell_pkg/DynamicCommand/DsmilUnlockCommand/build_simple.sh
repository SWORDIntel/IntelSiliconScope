#!/bin/bash
#
# Simple EDK2 Build Script for DsmilUnlockCommand
# Uses the EDK2 workspace directly
#

set -e

EDK2_ROOT="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"

if [ ! -d "$EDK2_ROOT" ]; then
    echo "ERROR: EDK2 root not found at $EDK2_ROOT"
    exit 1
fi

cd "$EDK2_ROOT"

# Set up environment
export WORKSPACE="$EDK2_ROOT"
export PACKAGES_PATH="$WORKSPACE"
export PYTHON_COMMAND=python3
export PYTHONHASHSEED=1

# Add BaseTools to PATH
export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"

# Ensure Conf files exist
if [ ! -f "Conf/target.txt" ]; then
    echo "Setting up Conf files..."
    mkdir -p Conf
    cp BaseTools/Conf/target.txt.template Conf/target.txt 2>/dev/null || true
    cp BaseTools/Conf/tools_def.txt.template Conf/tools_def.txt 2>/dev/null || true
    cp BaseTools/Conf/build_rule.txt.template Conf/build_rule.txt 2>/dev/null || true
fi

echo "================================================================================"
echo "Building DSMIL Unlock Dynamic Command"
echo "================================================================================"
echo "EDK2 Root: $EDK2_ROOT"
echo "WORKSPACE: $WORKSPACE"
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
    echo "================================================================================"
    exit 0
else
    echo ""
    echo "================================================================================"
    echo "✗ Build failed"
    echo "================================================================================"
    exit 1
fi
