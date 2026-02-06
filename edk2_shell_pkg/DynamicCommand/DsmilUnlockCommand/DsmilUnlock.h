/** @file
  DSMIL Unlock Command - Enhanced UEFI Shell Dynamic Command
  Integrates: MSR tools, CCTK, Clearance, Device255, VSEC, HAP unlock
  
  Copyright (c) 2025, DSMIL Project. All rights reserved.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef __DSMIL_UNLOCK_H__
#define __DSMIL_UNLOCK_H__

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/ShellLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Protocol/ShellDynamicCommand.h>
#include <Protocol/ShellParameters.h>
#include <Protocol/Shell.h>
#include <IndustryStandard/Acpi.h>

// MSR Coordination Registers (from clearance_set.c)
#define MSR_COORD_1A0  0x1A0
#define MSR_COORD_1A4  0x1A4
#define MSR_COORD_1AD  0x1AD
#define MSR_COORD_1AE  0x1AE
#define MSR_COORD_1AF  0x1AF
#define MSR_COORD_1B0  0x1B0

// Common MSRs
#define MSR_IA32_MISC_ENABLE      0x1A0
#define MSR_IA32_FEATURE_CONTROL  0x3A
#define MSR_XCR0                  0xD
#define MSR_IA32_XSS              0xDA0
#define MSR_IA32_BIOS_UPDT_TRIG   0x79
#define MSR_IA32_BIOS_SIGN_ID     0x8B

// VSEC/PMT MMIO Base (discovered) - ALL 21 registers
#define VSEC_MMIO_BASE            0x5019240000ULL
#define VSEC_ENG_MODE             0x0000
#define VSEC_DEBUG_CTRL           0x0004
#define VSEC_FUSE_OVERRIDE        0x0008
#define VSEC_SECURITY_BYPASS       0x000C
#define VSEC_CTRL_REG             0x0014
#define VSEC_STATUS               0x0018
#define VSEC_FEAT_UNLOCK_REG      0x0100
#define VSEC_CPU_CAPS_OVERRIDE    0x0104
#define VSEC_FUSE_MAP_CTRL        0x0108
#define VSEC_HIDDEN_MSR           0x010C
#define VSEC_AVX512_UNLOCK_REG    0x0200
#define VSEC_AMX_UNLOCK_REG       0x0204
#define VSEC_TME_UNLOCK           0x0208
#define VSEC_SGX_UNLOCK           0x020C
#define VSEC_TDX_UNLOCK           0x0210
#define VSEC_ME_CONTROL           0x0300
#define VSEC_ME_STATUS            0x0304
#define VSEC_ME_VERSION           0x0308
#define VSEC_CSME_BYPASS          0x030C
#define VSEC_BOOTGUARD_CTRL       0x0400
#define VSEC_SECURE_BOOT_CTRL      0x0404
#define VSEC_BIOS_LOCK_CTRL       0x0408

// HECI MMIO Base (discovered) - All registers
#define HECI_MMIO_BASE            0x50192DD000ULL
#define HECI_ME_CSR_HA            0x00
#define HECI_ME_CSR_ME            0x04
#define HECI_DOWNGRADE_EN         0x04
#define HECI_TARGET_VER           0x08
#define HECI_CPU_SIG              0x0C
#define HECI_CMD                  0x10
#define HECI_DOORBELL             0x14
#define HECI_RESULT               0x18
#define HECI_HFSTS1               0x40

// SMBus MMIO Base (for Device255)
#define SMBUS_MMIO_BASE           0x50192DC000ULL
#define SMBUS_SLAVE_ADDR          0x04
#define SMBUS_DATA_0              0x05
#define SMBUS_DATA_1              0x06
#define SMBUS_CONTROL             0x02
#define DEVICE255_SMBUS_ADDR      0xFF

// Host Bridge PCI Address
#define HOST_BRIDGE_PCI_ADDR      0x00000000  // 00:00.0
#define HOST_BRIDGE_CTRL          0xEC
#define HOST_BRIDGE_STATUS        0xF0

// I2C Controllers
#define I2C_CTRL0_MMIO            0x50192DE000ULL
#define I2C_CTRL3_MMIO            0x50192DF000ULL

// NPU MMIO Base
#define NPU_MMIO_BASE             0x50192E2000ULL

// Clearance Values
#define CLEARANCE_LAYER9          0xFF090909
#define CLEARANCE_ATOMAL          8
#define CAPS_ALL_ENABLED          0xFFFF
#define CAPS_NO_LOCKS             0x0000

// ME Commands (6 different HAP methods)
#define ME_CMD_HAP_OVERRIDE       0x85FF
#define ME_CMD_FEATURE_UNLOCK     0x8600
#define ME_CMD_FLEX_FABRIC        0x8601
#define ME_CMD_SYSTEM_UNLOCK      0x8602
#define ME_CMD_MKHI_SEC_UNLOCK    0x0302  // MKHI Group 0x03, Command 0x02
#define ME_CMD_MKHI_ENG_MODE      0x0303  // MKHI Group 0x03, Command 0x03
#define ME_CMD_MICROCODE_OVERRIDE 0x8505

// Function prototypes
EFI_STATUS
EFIAPI
DsmilUnlockCommandHandler (
  IN EFI_SHELL_DYNAMIC_COMMAND_PROTOCOL  *This,
  IN EFI_SYSTEM_TABLE                    *SystemTable,
  IN EFI_SHELL_PARAMETERS_PROTOCOL        *ShellParameters,
  IN EFI_SHELL_PROTOCOL                  *Shell
  );

CHAR16 *
EFIAPI
DsmilUnlockCommandGetHelp (
  IN EFI_SHELL_DYNAMIC_COMMAND_PROTOCOL  *This,
  IN CONST CHAR8                         *Language
  );

// MSR Operations
EFI_STATUS
DsmilMsrRead (
  IN UINT32  MsrAddress,
  OUT UINT64 *Value
  );

EFI_STATUS
DsmilMsrWrite (
  IN UINT32  MsrAddress,
  IN UINT64  Value
  );

// Clearance Operations
EFI_STATUS
DsmilSetClearance (
  IN UINT32  ClearanceValue
  );

// Device255 Operations
EFI_STATUS
DsmilDevice255Unlock (
  VOID
  );

// VSEC Operations (comprehensive - all 21 registers)
EFI_STATUS
DsmilVsecUnlock (
  IN BOOLEAN  Aggressive
  );

// HAP Operations (6 different methods)
EFI_STATUS
DsmilActivateHap (
  VOID
  );

// Host Bridge Operations
EFI_STATUS
DsmilHostBridgeUnlock (
  VOID
  );

// Microcode Staging
EFI_STATUS
DsmilStageMicrocode (
  IN UINT8  MicrocodeVersion
  );

// I2C Controller Unlock
EFI_STATUS
DsmilI2CUnlock (
  VOID
  );

// Additional Hardware Unlocks
EFI_STATUS
DsmilAdditionalHardwareUnlock (
  VOID
  );

// Coordination MSR Operations
EFI_STATUS
DsmilCoordinateMsrs (
  VOID
  );

// Full Unlock Sequence
EFI_STATUS
DsmilFullUnlock (
  IN CHAR16  *Mode
  );

#endif // __DSMIL_UNLOCK_H__
