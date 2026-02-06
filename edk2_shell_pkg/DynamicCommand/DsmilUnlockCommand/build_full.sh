#!/bin/bash
#
# Full EDK2 Build - Uses PlatformBuildClassObject for complete build
#

set -e

EDK2_ROOT="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"

if [ ! -d "$EDK2_ROOT" ]; then
    echo "ERROR: EDK2 root not found"
    exit 1
fi

cd "$EDK2_ROOT"

# Set up environment
export WORKSPACE="$EDK2_ROOT"
export PACKAGES_PATH="$WORKSPACE"
export EDK_TOOLS_PATH="$WORKSPACE/BaseTools"
export PYTHON_COMMAND=python3
export PYTHONHASHSEED=1
export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"
export PYTHONPATH="$WORKSPACE/BaseTools/Source/Python${PYTHONPATH:+:$PYTHONPATH}"

echo "================================================================================"
echo "Full EDK2 Build - DsmilUnlockCommand"
echo "================================================================================"
echo ""

# Use Python to run the full build process
python3 << 'PYTHON_SCRIPT'
import sys
import os

# Set up paths
workspace = os.getcwd()
sys.path.insert(0, os.path.join(workspace, 'BaseTools', 'Source', 'Python'))

try:
    from Workspace.WorkspaceDatabase import WorkspaceDatabase
    from Workspace.BuildClassObject import PlatformBuildClassObject
    import Common.GlobalData as GlobalData
    from Common.MultipleWorkspace import MultipleWorkspace as mws
    
    # Initialize global data
    GlobalData.gWorkspace = workspace
    GlobalData.gCommandLineDefines = {}
    GlobalData.gGlobalDefines = {'WORKSPACE': workspace}
    mws.setWs(GlobalData.gWorkspace, os.getenv('PACKAGES_PATH', ''))
    
    # Create workspace database
    ws_db = WorkspaceDatabase()
    print("Workspace database initialized")
    
    # Get platform build object
    platform_key = ('ShellPkg/ShellPkg.dsc', 'X64', 'RELEASE', 'GCC5')
    platform = ws_db.BuildObject[platform_key]
    print(f"Platform: {platform.PlatformName}")
    
    # Get module build object
    module_key = ('ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf', 'X64', 'RELEASE', 'GCC5')
    module = ws_db.BuildObject[module_key]
    print(f"Module: {module.BaseName}")
    
    # Create platform build class and build
    platform_build = PlatformBuildClassObject(platform, ws_db, platform_key[1], platform_key[2], platform_key[3])
    print("Platform build class created")
    
    # Build the module
    print("Starting build process...")
    platform_build.BuildModule(module, platform_build.Modules)
    print("Build completed successfully!")
    
except Exception as e:
    print(f"Build error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT

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
    echo "✗ Build failed - output not found"
    echo "================================================================================"
    exit 1
fi
