# Building DSMIL Unlock Dynamic Command

## Prerequisites

1. **EDK II BaseTools** - Must be built first
2. **Python 3** - Required for build system
3. **GCC 5+** - For X64 architecture builds
4. **EDK II Environment** - WORKSPACE and PACKAGES_PATH set

## Build Steps

### 1. Setup Environment

```bash
cd /path/to/edk2
export WORKSPACE=$(pwd)
export PACKAGES_PATH=$WORKSPACE
export PYTHON_COMMAND=python3
export PATH=$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH
```

### 2. Build BaseTools (if not already built)

```bash
cd BaseTools
make
cd ..
```

### 3. Build the Dynamic Command

```bash
# Method 1: Using build wrapper (if available)
./BaseTools/BinWrappers/PosixLike/build \
  -p ShellPkg/ShellPkg.dsc \
  -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \
  -a X64 \
  -t GCC5

# Method 2: Direct Python (if build wrapper doesn't work)
python3 BaseTools/Source/Python/Workspace/BuildClassObject.py \
  -p ShellPkg/ShellPkg.dsc \
  -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \
  -a X64 \
  -t GCC5
```

### 4. Output Location

The built EFI file will be at:
```
Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi
```

### 5. Install to EFI Partition

```bash
# Copy to EFI partition
cp Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi /mnt/sdb1/EFI/BOOT/

# Or copy to EFI shell directory
cp Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi /mnt/sdb1/EFI/Shell/
```

## Troubleshooting

### Build Tool Not Found

If `build` command is not found:
1. Check BaseTools is built: `ls BaseTools/BinWrappers/PosixLike/build`
2. Add to PATH: `export PATH=$WORKSPACE/BaseTools/BinWrappers/PosixLike:$PATH`

### Python Issues

If Python errors occur:
1. Use `python3` explicitly: `export PYTHON_COMMAND=python3`
2. Check Python version: `python3 --version` (needs 3.6+)

### Missing Dependencies

If build fails with missing modules:
1. Install EDK II Python dependencies
2. Check BaseTools/Source/Python structure

## Integration

The dynamic command is already added to `ShellPkg.dsc`:
```
ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf {
  <PcdsFixedAtBuild>
    gEfiShellPkgTokenSpaceGuid.PcdShellLibAutoInitialize|FALSE
}
```

## Usage After Build

1. Boot to UEFI shell
2. Load the dynamic command:
   ```
   Shell> load DsmilUnlockDynamicCommand.efi
   ```
3. Use the command:
   ```
   Shell> dsmil-unlock full aggressive
   ```

## Alternative: Standalone Build

If integrated build doesn't work, you can build just this module:

```bash
# Build only the dynamic command module
build -p ShellPkg/ShellPkg.dsc \
  -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf \
  -a X64 \
  -t GCC5 \
  --only-module
```
