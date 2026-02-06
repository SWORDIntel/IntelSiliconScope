# EDK2 Shell Package (ShellPkg)

## Status: INCOMPLETE

This is the entire EDK2 ShellPkg directory, including the custom DSMIL unlock dynamic command.

## Location

Moved from:
```
tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2/ShellPkg/
```

Current location:
```
tools/edk2_shell_pkg/
```

## Contents

- **Shell Libraries**: UefiShellLib, UefiShellCommandLib, etc.
- **Shell Applications**: Main shell application
- **Dynamic Commands**: Including custom DSMIL unlock command
- **Level Commands**: Level 1, 2, 3 commands
- **Network Commands**: Network-related shell commands
- **Debug Commands**: Debug utilities

## Custom Dynamic Command

The DSMIL unlock dynamic command is located at:
```
DynamicCommand/DsmilUnlockCommand/
```

See `DynamicCommand/DsmilUnlockCommand/README.md` for details.

## Build Status

⚠️ **INCOMPLETE** - Requires complete EDK2 build environment:
- BaseTools built
- Proper workspace initialization
- Full EDK2 tree structure
- AutoGen and compilation phases

## Build Requirements

To build this shell package, you need:
1. Complete EDK2 workspace
2. BaseTools compiled
3. Proper environment setup (`source edksetup.sh`)
4. All EDK2 dependencies

## Usage

This is part of the EDK2 project. To use:
1. Place back in EDK2 tree: `edk2/ShellPkg/`
2. Set up EDK2 environment
3. Build: `build -p ShellPkg/ShellPkg.dsc -a X64 -t GCC5`

## Note

This package is incomplete without the full EDK2 build system. The source code is present but compilation requires the complete EDK2 infrastructure.
