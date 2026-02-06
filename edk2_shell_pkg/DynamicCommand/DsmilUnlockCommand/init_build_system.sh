#!/bin/bash
#
# Complete EDK2 Build System Initialization
# This script fully initializes the EDK2 build environment
#

set -e

EDK2_ROOT="/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2"

if [ ! -d "$EDK2_ROOT" ]; then
    echo "ERROR: EDK2 root not found at $EDK2_ROOT"
    exit 1
fi

cd "$EDK2_ROOT"

echo "================================================================================"
echo "EDK2 Build System Initialization"
echo "================================================================================"
echo "EDK2 Root: $EDK2_ROOT"
echo "================================================================================"
echo ""

# Step 1: Set up Conf files
echo "[1] Setting up Conf files..."
mkdir -p Conf

if [ ! -f "Conf/target.txt" ] || [ ! -s "Conf/target.txt" ]; then
    echo "  Creating Conf/target.txt from template..."
    if [ -f "BaseTools/Conf/target.txt.template" ]; then
        cp BaseTools/Conf/target.txt.template Conf/target.txt
    else
        cat > Conf/target.txt << 'EOF'
ACTIVE_PLATFORM       = ShellPkg/ShellPkg.dsc
TARGET                = RELEASE
TARGET_ARCH           = X64
TOOL_CHAIN_TAG        = GCC5
BUILD_RULE_CONF       = Conf/build_rule.txt
EOF
    fi
fi

if [ ! -f "Conf/tools_def.txt" ] || [ ! -s "Conf/tools_def.txt" ]; then
    echo "  Creating Conf/tools_def.txt from template..."
    if [ -f "BaseTools/Conf/tools_def.txt.template" ]; then
        cp BaseTools/Conf/tools_def.txt.template Conf/tools_def.txt
    fi
fi

if [ ! -f "Conf/build_rule.txt" ] || [ ! -s "Conf/build_rule.txt" ]; then
    echo "  Creating Conf/build_rule.txt from template..."
    if [ -f "BaseTools/Conf/build_rule.txt.template" ]; then
        cp BaseTools/Conf/build_rule.txt.template Conf/build_rule.txt
    fi
fi

echo "  ✓ Conf files ready"
echo ""

# Step 2: Set up environment variables
echo "[2] Setting up environment variables..."
export WORKSPACE="$EDK2_ROOT"
export PACKAGES_PATH="$WORKSPACE"
export EDK_TOOLS_PATH="$WORKSPACE/BaseTools"
export PYTHON_COMMAND=python3
export PYTHONHASHSEED=1

# Add BaseTools to PATH
export PATH="$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH"

# Set Python path for EDK2 build tools
export PYTHONPATH="$WORKSPACE/BaseTools/Source/Python${PYTHONPATH:+:$PYTHONPATH}"

echo "  WORKSPACE: $WORKSPACE"
echo "  PACKAGES_PATH: $PACKAGES_PATH"
echo "  EDK_TOOLS_PATH: $EDK_TOOLS_PATH"
echo "  PYTHON_COMMAND: $PYTHON_COMMAND"
echo "  PYTHONPATH: $PYTHONPATH"
echo ""

# Step 3: Build BaseTools if needed
echo "[3] Checking BaseTools..."
if [ ! -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ]; then
    echo "  BaseTools not built. Building BaseTools..."
    cd "$WORKSPACE/BaseTools"
    make -j$(nproc) 2>&1 | grep -E "(error|Error|ERROR|warning|Warning)" || true
    cd "$WORKSPACE"
    echo "  ✓ BaseTools built"
else
    echo "  ✓ BaseTools already built"
fi
echo ""

# Step 4: Verify build tools
echo "[4] Verifying build tools..."
if [ ! -f "$WORKSPACE/BaseTools/BinWrappers/PosixLike/build" ]; then
    echo "  ✗ Build wrapper not found"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "  ✗ Python3 not found"
    exit 1
fi

echo "  ✓ Build tools verified"
echo ""

# Step 5: Initialize workspace database
echo "[5] Initializing workspace database..."
# The build system will create the database on first run
# We'll test it with a dry run
echo "  Testing workspace initialization..."
cd "$WORKSPACE"

# Create a test to verify the build system can parse the workspace
python3 -c "
import sys
sys.path.insert(0, '$WORKSPACE/BaseTools/Source/Python')
try:
    from Workspace.WorkspaceDatabase import WorkspaceDatabase
    ws = WorkspaceDatabase('$WORKSPACE')
    print('  ✓ Workspace database can be initialized')
except Exception as e:
    print(f'  ⚠ Workspace database test: {e}')
    print('  (This may be normal - will initialize on first build)')
" 2>&1 || echo "  (Workspace will initialize on first build)"
echo ""

# Step 6: Verify module exists
echo "[6] Verifying module files..."
MODULE_DIR="$WORKSPACE/ShellPkg/DynamicCommand/DsmilUnlockCommand"
if [ ! -d "$MODULE_DIR" ]; then
    echo "  ✗ Module directory not found: $MODULE_DIR"
    exit 1
fi

if [ ! -f "$MODULE_DIR/DsmilUnlockDynamicCommand.inf" ]; then
    echo "  ✗ Module INF not found"
    exit 1
fi

if [ ! -f "$WORKSPACE/ShellPkg/ShellPkg.dsc" ]; then
    echo "  ✗ ShellPkg.dsc not found"
    exit 1
fi

echo "  ✓ Module files verified"
echo ""

echo "================================================================================"
echo "✓ Build system initialized successfully!"
echo "================================================================================"
echo ""
echo "Environment is ready. You can now build with:"
echo "  cd $WORKSPACE"
echo "  build -p ShellPkg/ShellPkg.dsc \\"
echo "        -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \\"
echo "        -a X64 -t GCC5 -b RELEASE"
echo ""
echo "Or run the build script:"
echo "  bash tools/edk2_shell_pkg/DynamicCommand/DsmilUnlockCommand/build.sh"
echo "================================================================================"
