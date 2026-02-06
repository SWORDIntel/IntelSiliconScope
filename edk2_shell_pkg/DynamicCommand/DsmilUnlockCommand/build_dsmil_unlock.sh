#!/bin/bash
#
# Build script for DSMIL Unlock Dynamic Command
#
# This script builds the dsmil-unlock dynamic command for UEFI shell
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find EDK2 root by looking for edksetup.sh
EDK2_ROOT="$SCRIPT_DIR"
while [ ! -f "$EDK2_ROOT/edksetup.sh" ] && [ "$EDK2_ROOT" != "/" ]; do
    EDK2_ROOT="$(dirname "$EDK2_ROOT")"
done
if [ ! -f "$EDK2_ROOT/edksetup.sh" ]; then
    echo "ERROR: Could not find EDK2 root (edksetup.sh not found)"
    exit 1
fi

echo "================================================================================"
echo "Building DSMIL Unlock Dynamic Command"
echo "================================================================================"
echo "EDK2 Root: $EDK2_ROOT"
echo "Module: ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf"
echo "================================================================================"
echo ""

cd "$EDK2_ROOT"

# Set up environment
export WORKSPACE="$EDK2_ROOT"
export PACKAGES_PATH="$WORKSPACE"
export PYTHON_COMMAND=python3

# Add BaseTools to PATH
export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"

# Check if BaseTools is built
if [ ! -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ]; then
    echo "ERROR: BaseTools not built. Building BaseTools first..."
    cd "$WORKSPACE/BaseTools"
    make -j$(nproc)
    cd "$WORKSPACE"
fi

# Check if build.py exists (may need to create it)
if [ ! -f "$WORKSPACE/BaseTools/Source/Python/build/build.py" ]; then
    echo "WARNING: build.py not found. The build system may need to be set up."
    echo "This EDK2 version may use a different build system."
    echo ""
    echo "Alternative build methods:"
    echo "1. Use stuart build (if available)"
    echo "2. Build manually using PlatformBuildClassObject"
    echo "3. Use a pre-built shell and load the module separately"
    exit 1
fi

# Build the dynamic command
echo "Building DSMIL Unlock Dynamic Command..."
echo ""

# Try using the build wrapper
if [ -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ]; then
    "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" \
        -p ShellPkg/ShellPkg.dsc \
        -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \
        -a X64 \
        -t GCC5 \
        "$@"
else
    echo "ERROR: Build wrapper not found"
    exit 1
fi

# Check if build succeeded
if [ -f "$WORKSPACE/Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi" ]; then
    echo ""
    echo "================================================================================"
    echo "✓ Build successful!"
    echo "================================================================================"
    echo "Output: $WORKSPACE/Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi"
    echo ""
    echo "To install:"
    echo "  cp Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi /mnt/sdb1/EFI/BOOT/"
    echo ""
    echo "To use in UEFI shell:"
    echo "  Shell> load DsmilUnlockDynamicCommand.efi"
    echo "  Shell> dsmil-unlock full aggressive"
    echo "================================================================================"
else
    echo ""
    echo "================================================================================"
    echo "✗ Build failed or output not found"
    echo "================================================================================"
    echo "Check build log for errors"
    exit 1
fi
