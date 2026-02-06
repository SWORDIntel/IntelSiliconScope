#!/bin/bash
#
# Build script for ME Firmware Restoration UEFI Application
#
# This script builds the MeRestoreApp for UEFI shell
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find EDK2 root by looking for edksetup.sh
EDK2_ROOT="$SCRIPT_DIR"
while [ ! -f "$EDK2_ROOT/edksetup.sh" ] && [ "$EDK2_ROOT" != "/" ]; do
    EDK2_ROOT="$(dirname "$EDK2_ROOT")"
done
if [ ! -f "$EDK2_ROOT/edksetup.sh" ]; then
    # Try alternative location
    EDK2_ROOT="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"
    if [ ! -f "$EDK2_ROOT/edksetup.sh" ]; then
        echo "ERROR: Could not find EDK2 root (edksetup.sh not found)"
        echo "Please set EDK2_ROOT environment variable or place edksetup.sh in the path"
        exit 1
    fi
fi

echo "================================================================================"
echo "Building ME Firmware Restoration UEFI Application"
echo "================================================================================"
echo "EDK2 Root: $EDK2_ROOT"
echo "Module: ShellPkg/Application/MeRestoreApp/MeRestoreApp.inf"
echo "================================================================================"
echo ""

cd "$EDK2_ROOT"

# Set up environment
export WORKSPACE="$EDK2_ROOT"
export PACKAGES_PATH="$WORKSPACE"
export PYTHON_COMMAND=python3
export PYTHONPATH="$EDK2_ROOT/BaseTools/Source/Python:$PYTHONPATH"

# Source edksetup to initialize environment
if [ -f "$EDK2_ROOT/edksetup.sh" ]; then
    echo "Sourcing edksetup.sh to initialize EDK2 environment..."
    source "$EDK2_ROOT/edksetup.sh"
    echo "EDK2 environment initialized"
    echo "WORKSPACE: $WORKSPACE"
    echo "EDK_TOOLS_PATH: $EDK_TOOLS_PATH"
    echo ""
fi

# Add BaseTools to PATH
if [ -d "$WORKSPACE/BaseTools/BinWrappers/PosixLike" ]; then
    export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"
fi

# Check if BaseTools is built
if [ ! -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ] && [ -d "$WORKSPACE/BaseTools" ]; then
    echo "BaseTools not built. Building BaseTools first..."
    cd "$WORKSPACE/BaseTools"
    make -j$(nproc) || {
        echo "WARNING: BaseTools build failed, trying to continue anyway..."
    }
    cd "$WORKSPACE"
fi

# Copy ShellPkg to EDK2 if needed
SHELLPKG_SRC="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/edk2_shell_pkg"
SHELLPKG_DST="$WORKSPACE/ShellPkg"

if [ ! -d "$SHELLPKG_DST" ] && [ -d "$SHELLPKG_SRC" ]; then
    echo "Copying ShellPkg to EDK2 workspace..."
    cp -r "$SHELLPKG_SRC" "$SHELLPKG_DST"
fi

# Build the application
echo "Building MeRestoreApp..."
echo ""

# Use the build wrapper with fixed Python environment
"$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" \
    -p ShellPkg/ShellPkg.dsc \
    -m ShellPkg/Application/MeRestoreApp/MeRestoreApp.inf \
    -a X64 \
    -t GCC5 \
    -b RELEASE \
    "$@"

# Check if build succeeded
BUILD_OUTPUT="$WORKSPACE/Build/Shell/RELEASE_GCC5/X64/MeRestoreApp.efi"
if [ ! -f "$BUILD_OUTPUT" ]; then
    # Try DEBUG build
    BUILD_OUTPUT="$WORKSPACE/Build/Shell/DEBUG_GCC5/X64/MeRestoreApp.efi"
fi

if [ -f "$BUILD_OUTPUT" ]; then
    echo ""
    echo "================================================================================"
    echo "✓ Build successful!"
    echo "================================================================================"
    echo "Output: $BUILD_OUTPUT"
    echo ""
    
    # Find EFI partition
    EFI_PARTITION=""
    for dev in /dev/sd*[0-9] /dev/nvme*n* /dev/mmcblk*p*; do
        if [ -b "$dev" ]; then
            MOUNT_POINT=$(findmnt -n -o TARGET "$dev" 2>/dev/null || echo "")
            if [ -n "$MOUNT_POINT" ] && mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
                if [ -d "$MOUNT_POINT/EFI" ] || [ -d "$MOUNT_POINT/efi" ]; then
                    EFI_PARTITION="$MOUNT_POINT"
                    break
                fi
            fi
        fi
    done
    
    if [ -n "$EFI_PARTITION" ]; then
        echo "Found EFI partition: $EFI_PARTITION"
        EFI_BOOT_DIR="$EFI_PARTITION/EFI/BOOT"
        if [ ! -d "$EFI_BOOT_DIR" ]; then
            EFI_BOOT_DIR="$EFI_PARTITION/efi/boot"
        fi
        
        if [ -d "$EFI_BOOT_DIR" ]; then
            echo "Copying to EFI partition..."
            cp "$BUILD_OUTPUT" "$EFI_BOOT_DIR/MeRestoreApp.efi"
            echo "✓ Installed to: $EFI_BOOT_DIR/MeRestoreApp.efi"
        else
            echo "⚠ EFI/BOOT directory not found, manual copy required"
        fi
    else
        echo "⚠ EFI partition not found, manual copy required"
        echo ""
        echo "To install manually:"
        echo "  sudo mount /dev/sdX1 /mnt/efi"
        echo "  sudo cp $BUILD_OUTPUT /mnt/efi/EFI/BOOT/MeRestoreApp.efi"
        echo "  sudo umount /mnt/efi"
    fi
    
    echo ""
    echo "To use in UEFI shell:"
    echo "  Shell> MeRestoreApp.efi dump.bin"
    echo "  Shell> MeRestoreApp.efi dump.bin -hap  # For HAP mode"
    echo "================================================================================"
else
    echo ""
    echo "================================================================================"
    echo "✗ Build failed or output not found"
    echo "================================================================================"
    echo "Check build log for errors"
    echo "Expected output location: $WORKSPACE/Build/Shell/RELEASE_GCC5/X64/MeRestoreApp.efi"
    exit 1
fi
