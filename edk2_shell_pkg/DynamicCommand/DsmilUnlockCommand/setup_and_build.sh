#!/bin/bash
#
# Complete EDK2 Build System Setup and Build Script
# Sets up EDK2 environment and builds DsmilUnlockCommand
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# DsmilUnlockCommand -> DynamicCommand -> edk2_shell_pkg
SHELLPKG_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# edk2_shell_pkg -> tools -> DSMILSystem root
DSMIL_ROOT="$(cd "$SHELLPKG_DIR/.." && pwd)"

# Find EDK2 root
EDK2_ROOT="$DSMIL_ROOT/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"
if [ ! -d "$EDK2_ROOT" ]; then
    # Try alternative path
    EDK2_ROOT="$DSMIL_ROOT/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"
fi

if [ ! -f "$EDK2_ROOT/edksetup.sh" ]; then
    echo "ERROR: EDK2 root not found at $EDK2_ROOT"
    echo "Please ensure EDK2 is available at that location"
    exit 1
fi

echo "================================================================================"
echo "EDK2 Build System Setup and Build"
echo "================================================================================"
echo "EDK2 Root: $EDK2_ROOT"
echo "ShellPkg Dir: $SHELLPKG_DIR"
echo "DSMIL Root: $DSMIL_ROOT"
echo "================================================================================"
echo ""

cd "$EDK2_ROOT"

# Source edksetup.sh to set up environment
echo "[1] Setting up EDK2 environment..."
if [ -f "edksetup.sh" ]; then
    # Source the setup script (we'll export the variables manually)
    . edksetup.sh >/dev/null 2>&1 || true
fi

# Set up environment variables
export WORKSPACE="$EDK2_ROOT"
# PACKAGES_PATH should include directories containing .dec files
# Our ShellPkg is at tools/edk2_shell_pkg, so we need its parent
export PACKAGES_PATH="$SHELLPKG_DIR:$WORKSPACE"
export PYTHON_COMMAND=python3
export PYTHONHASHSEED=1

# Add BaseTools to PATH
export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"

echo "  WORKSPACE: $WORKSPACE"
echo "  PACKAGES_PATH: $PACKAGES_PATH"
echo "  PYTHON_COMMAND: $PYTHON_COMMAND"
echo ""

# Check if BaseTools is built
echo "[2] Checking BaseTools..."
if [ ! -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ]; then
    echo "  BaseTools not built. Building BaseTools..."
    cd "$WORKSPACE/BaseTools"
    make -j$(nproc)
    cd "$WORKSPACE"
    echo "  ✓ BaseTools built"
else
    echo "  ✓ BaseTools already built"
fi
echo ""

# Verify build tool
if [ ! -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ]; then
    echo "ERROR: Build tool not found after BaseTools build"
    exit 1
fi

# Check if ShellPkg.dsc exists in EDK2 workspace
SHELLPKG_DSC="$WORKSPACE/ShellPkg/ShellPkg.dsc"
if [ ! -f "$SHELLPKG_DSC" ]; then
    echo "ERROR: ShellPkg.dsc not found at $SHELLPKG_DSC"
    exit 1
fi

# Verify the module exists
MODULE_INF="$WORKSPACE/ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf"
if [ ! -f "$MODULE_INF" ]; then
    echo "ERROR: Module INF not found at $MODULE_INF"
    echo "Copying from source location..."
    mkdir -p "$WORKSPACE/ShellPkg/DynamicCommand/DsmilUnlockCommand"
    cp -r "$SHELLPKG_DIR/DynamicCommand/DsmilUnlockCommand/"* "$WORKSPACE/ShellPkg/DynamicCommand/DsmilUnlockCommand/"
fi

echo "[3] Building DSMIL Unlock Dynamic Command..."
echo "  Platform: $SHELLPKG_DSC"
echo "  Module: ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf"
echo "  Architecture: X64"
echo "  Toolchain: GCC5"
echo ""

# Build the dynamic command
"$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" \
    -p ShellPkg/ShellPkg.dsc \
    -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \
    -a X64 \
    -t GCC5 \
    -b RELEASE \
    "$@"

BUILD_OUTPUT="$WORKSPACE/Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi"

# Check if build succeeded
if [ -f "$BUILD_OUTPUT" ]; then
    echo ""
    echo "================================================================================"
    echo "✓ Build successful!"
    echo "================================================================================"
    echo "Output: $BUILD_OUTPUT"
    echo ""
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
    echo "✗ Build failed or output not found"
    echo "================================================================================"
    echo "Expected output: $BUILD_OUTPUT"
    echo ""
    echo "Check build logs in: $WORKSPACE/Build/Shell/RELEASE_GCC5/X64/"
    exit 1
fi
