# DSMIL Unlock Enhanced UEFI Shell Command

## Overview

This is an enhanced UEFI shell DynamicCommand that integrates:
- **Milspec MSR Tools**: MSR read/write operations
- **Milspec CCTK Tools**: BIOS token manipulation
- **Custom Unlock Work**: Clearance, Device255, VSEC, HAP activation

## Features

### MSR Operations
- `dsmil-unlock msr-read <addr>` - Read MSR register
- `dsmil-unlock msr-write <addr> <val>` - Write MSR register
- `dsmil-unlock coordinate` - Set MSR coordination registers (0x1A0, 0x1A4, 0x1AD, 0x1AE, 0x1AF, 0x1B0)

### Clearance Operations
- `dsmil-unlock clearance [value]` - Set firmware clearance (default: 0xFF090909 Layer 9)

### Device255 Operations
- `dsmil-unlock device255` - Unlock Device255 (Master Crypto Controller) via SMBus

### VSEC Operations
- `dsmil-unlock vsec [aggressive]` - Unlock VSEC/PMT registers

### HAP Operations
- `dsmil-unlock hap` - Activate HAP (High Assurance Platform) mode

### Full Unlock Sequence
- `dsmil-unlock full [safe|aggressive|complete]` - Complete unlock sequence

## Build Instructions

1. Navigate to EDK2 root:
   ```bash
   cd /path/to/edk2
   ```

2. Build the command:
   ```bash
   build -p ShellPkg/ShellPkg.dsc -m ShellPkg/DynamicCommand/DsmilUnlockCommand/DsmilUnlockDynamicCommand.inf
   ```

3. Copy to EFI partition:
   ```bash
   cp Build/Shell/RELEASE_GCC5/X64/DsmilUnlockDynamicCommand.efi /mnt/sdb1/EFI/BOOT/
   ```

## Usage Examples

```bash
# Read MSR coordination register
dsmil-unlock msr-read 0x1AD

# Set MSR coordination
dsmil-unlock coordinate

# Set maximum clearance
dsmil-unlock clearance

# Full unlock sequence (aggressive mode)
dsmil-unlock full aggressive
```

## Integration with Existing Tools

This command integrates functionality from:
- `tools/msr-tools/milspec_port/msr_milspec.c`
- `tools/CCTK/linux_port/cctk_milspec.c`
- `scripts/unlock/modules-*/clearance_direct/clearance_set.c`
- `scripts/unlock/modules-*/unified_microcode/device255_unlock.c`
- `scripts/unlock/modules-*/vsec_unlock/vsec_unlock.c`

## Addresses

All addresses are from `discovered_addresses_deep.txt`:
- VSEC MMIO Base: `0x5019240000`
- HECI MMIO Base: `0x50192DD000`
- SMBus MMIO Base: `0x50192DC000`
- NPU MMIO Base: `0x50192e2000`
