# Creating UEFI Application for ME Firmware Restoration

## Overview

A UEFI application can restore ME firmware from UEFI shell before the OS loads, potentially bypassing ME write protection since the ME may be less active during UEFI phase.

## Advantages of UEFI Application

1. **ME Less Active**: ME may not be fully active during UEFI phase
2. **Direct Hardware Access**: Full MMIO access to SPI controller
3. **File I/O Support**: Can read ME dump from EFI partition
4. **No OS Interference**: Runs before OS loads
5. **Better Error Handling**: Full C/C++ capabilities

## Implementation Plan

### 1. UEFI Application Structure

```c
// MeRestoreApp.c
#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Protocol/SimpleFileSystem.h>

// SPI Controller definitions
#define SPI_MMIO_BASE    0x7c120000ULL
#define SPI_HSFSTS_CTL   0x0000
#define SPI_FADDR        0x0008
#define SPI_FDATA0       0x0010
#define SPI_FRAP         0x0050
#define SPI_FREG2        0x005C

// ME Region
#define ME_START         0x00126000ULL
#define ME_END           0x00EC7FFFULL
#define ME_SIZE          (ME_END - ME_START + 1)

EFI_STATUS
EFIAPI
MeRestoreMain (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  // 1. Open ME dump file from EFI partition
  // 2. Map SPI controller MMIO
  // 3. Verify ME region addresses
  // 4. Disable write protection
  // 5. Write ME firmware in chunks
  // 6. Verify write completion
}
```

### 2. Key Functions Needed

#### SPI Controller Access
- Map MMIO region for SPI controller
- Read/write SPI registers
- Configure hardware sequencing

#### File I/O
- Open ME dump file from EFI partition
- Read file in chunks
- Handle file errors

#### Flash Write
- Write data to SPI FDATA registers
- Set flash address (FADDR)
- Configure HSFSTS_CTL for write
- Trigger write operation
- Wait for completion

### 3. Build Requirements

**EDK2 Environment**:
```bash
# Set up EDK2 workspace
export WORKSPACE=/path/to/edk2
source edksetup.sh

# Build application
build -p ShellPkg/ShellPkg.dsc \
      -m ShellPkg/Application/MeRestoreApp/MeRestoreApp.inf \
      -a X64 -t GCC5
```

**Application INF File**:
```ini
[Defines]
  INF_VERSION                    = 0x00010005
  BASE_NAME                      = MeRestoreApp
  FILE_GUID                      = [GUID]
  MODULE_TYPE                    = UEFI_APPLICATION
  VERSION_STRING                 = 1.0
  ENTRY_POINT                    = MeRestoreMain

[Sources]
  MeRestoreApp.c

[Packages]
  MdePkg/MdePkg.dec
  ShellPkg/ShellPkg.dec

[LibraryClasses]
  UefiApplicationEntryPoint
  UefiLib
  BaseMemoryLib
  MemoryAllocationLib
```

### 4. Usage

**From UEFI Shell**:
```shell
# Copy ME dump to EFI partition
fs0:
copy me_dump_16mb.bin fs0:\

# Run application
MeRestoreApp.efi fs0:\me_dump_16mb.bin
```

### 5. Advantages Over Kernel Module

1. **Timing**: Runs before ME is fully active
2. **Protection**: ME may not enforce write protection in UEFI
3. **Access**: Direct hardware access without OS interference
4. **Simplicity**: No kernel module complexity

### 6. Implementation Steps

1. **Create EDK2 Application**:
   - New directory: `ShellPkg/Application/MeRestoreApp/`
   - Source file: `MeRestoreApp.c`
   - INF file: `MeRestoreApp.inf`

2. **Implement SPI Access**:
   - MMIO mapping functions
   - Register read/write functions
   - Hardware sequencing functions

3. **Implement File I/O**:
   - Open file from EFI partition
   - Read in chunks (256 bytes)
   - Error handling

4. **Implement Flash Write**:
   - Write protection disable
   - Chunked write loop
   - Progress reporting
   - Verification

5. **Build and Test**:
   - Build with EDK2
   - Copy to EFI partition
   - Test from UEFI shell

## Current Status

**Shell Script Created**: `FLAGS/shared/uefi_restore_me_firmware.nsh`
- Basic structure
- Verification steps
- Limited by shell script capabilities

**Next Step**: Create full UEFI application with EDK2

## References

- EDK2 Documentation: https://github.com/tianocore/edk2
- UEFI Shell Programming: UEFI Shell Specification
- Intel SPI Controller: Intel Platform Controller Hub Datasheet
