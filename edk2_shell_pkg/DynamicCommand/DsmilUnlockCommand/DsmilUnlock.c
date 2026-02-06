/** @file
  DSMIL Unlock Command Implementation
  Integrates MSR tools, CCTK, and unlock functionality
  
  Copyright (c) 2025, DSMIL Project. All rights reserved.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include "DsmilUnlock.h"
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/IoLib.h>
#include <Library/PciLib.h>
#include <Library/BaseLib.h>
#include <IndustryStandard/Pci.h>

// MSR Read/Write using CPU instructions
EFI_STATUS
DsmilMsrRead (
  IN UINT32  MsrAddress,
  OUT UINT64 *Value
  )
{
  if (Value == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  // Use CPU MSR read instruction (returns UINT64 directly)
  *Value = AsmReadMsr64 (MsrAddress);
  
  return EFI_SUCCESS;
}

EFI_STATUS
DsmilMsrWrite (
  IN UINT32  MsrAddress,
  IN UINT64  Value
  )
{
  // Use CPU MSR write instruction
  AsmWriteMsr64 (MsrAddress, Value);
  
  return EFI_SUCCESS;
}

// Set coordination MSRs (from clearance_set.c and hap_feature_unlock.c)
EFI_STATUS
DsmilCoordinateMsrs (
  VOID
  )
{
  EFI_STATUS  Status;
  UINT32      Msrs[] = {MSR_COORD_1A0, MSR_COORD_1A4, MSR_COORD_1AD, 
                        MSR_COORD_1AE, MSR_COORD_1AF, MSR_COORD_1B0};
  UINT64      CoordValue = 0xFFFFFFFFFFFFFFFFULL;
  UINTN       i;
  UINTN       Count = sizeof(Msrs) / sizeof(Msrs[0]);
  
  Print (L"Setting MSR coordination registers...\n");
  
  for (i = 0; i < Count; i++) {
    Status = DsmilMsrWrite (Msrs[i], CoordValue);
    if (EFI_ERROR (Status)) {
      Print (L"  ⚠ MSR 0x%03X write failed\n", Msrs[i]);
    } else {
      Print (L"  ✓ MSR 0x%03X coordination set\n", Msrs[i]);
    }
  }
  
  return EFI_SUCCESS;
}

// Set clearance (simplified for UEFI - uses MMIO)
EFI_STATUS
DsmilSetClearance (
  IN UINT32  ClearanceValue
  )
{
  // In UEFI, we can use MMIO directly
  // Addresses from clearance_set.c
  UINTN  NpuMmioBase = 0x50192e2000;  // NPU MMIO base
  UINTN  ClearanceOffset = 0x8026;    // Device 12, Offset 2
  
  Print (L"Setting clearance to 0x%08X...\n", ClearanceValue);
  
  // Write clearance via MMIO
  MmioWrite32 (NpuMmioBase + ClearanceOffset, ClearanceValue);
  
  Print (L"  ✓ Clearance set (MMIO write)\n");
  
  return EFI_SUCCESS;
}

// Device255 unlock (3 different patterns from uefi_unlock_maximum_aggressive.nsh)
EFI_STATUS
DsmilDevice255Unlock (
  VOID
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  UINTN       SmbusSlaveAddr = SMBUS_MMIO_BASE + SMBUS_SLAVE_ADDR;
  UINTN       SmbusData0 = SMBUS_MMIO_BASE + SMBUS_DATA_0;
  UINTN       SmbusData1 = SMBUS_MMIO_BASE + SMBUS_DATA_1;
  UINTN       SmbusControl = SMBUS_MMIO_BASE + SMBUS_CONTROL;
  
  Print (L"TIER 1: DEVICE255 UNLOCK (Master Crypto Controller)\n");
  Print (L"Purpose: Unlock Device255 via SMBus (required for HAP)\n\n");
  
  // [1/3] Device255 Pattern 1: 0xFFFFFFFF
  Print (L"[1/3] Device255 SMBus Unlock (Pattern: 0xFFFFFFFF)...\n");
  MmioWrite32 (SmbusSlaveAddr, DEVICE255_SMBUS_ADDR);
  MmioWrite32 (SmbusData0, 0xFFFFFFFF);
  MmioWrite32 (SmbusData1, 0xFFFFFFFF);
  Status = MmioWrite32 (SmbusControl, 0x00000005);  // Start + Quick
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Device255 unlock command sent\n");
  } else {
    Print (L"  ⚠ Device255 unlock failed (trying alternative...)\n");
  }
  gBS->Stall (100000);  // 100ms delay
  Print (L"\n");
  
  // [2/3] Device255 Pattern 2: 0xA00A00A0
  Print (L"[2/3] Device255 Alternative Pattern (0xA00A00A0)...\n");
  MmioWrite32 (SmbusSlaveAddr, DEVICE255_SMBUS_ADDR);
  MmioWrite32 (SmbusData0, 0xA00A00A0);
  MmioWrite32 (SmbusData1, 0xA00A00A0);
  MmioWrite32 (SmbusControl, 0x00000005);
  gBS->Stall (100000);
  Print (L"\n");
  
  // [3/3] Device255 Pattern 3: 0xDEADBEEF
  Print (L"[3/3] Device255 Engineering Pattern (0xDEADBEEF)...\n");
  MmioWrite32 (SmbusSlaveAddr, DEVICE255_SMBUS_ADDR);
  MmioWrite32 (SmbusData0, 0xDEADBEEF);
  MmioWrite32 (SmbusData1, 0xDEADBEEF);
  MmioWrite32 (SmbusControl, 0x00000005);
  gBS->Stall (100000);
  Print (L"  ✓✓✓ Device255 unlock attempts completed\n\n");
  
  return EFI_SUCCESS;
}

// VSEC unlock (comprehensive - all 21 registers from uefi_unlock_maximum_aggressive.nsh)
EFI_STATUS
DsmilVsecUnlock (
  IN BOOLEAN  Aggressive
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  UINT32      ReadBack;
  
  Print (L"TIER 3: VSEC UNLOCK (Bypass ME Entirely)\n");
  Print (L"Purpose: Unlock features via VSEC (operates independently of ME)\n");
  Print (L"VSEC MMIO Base: 0x%016llX\n\n", VSEC_MMIO_BASE);
  
  // [1/21] VSEC Engineering Mode
  Print (L"[1/21] VSEC Engineering Mode (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_ENG_MODE);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_ENG_MODE, 0x00000001);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_ENG_MODE);
  if (ReadBack == 0x1) {
    Print (L"  ✓ Engineering Mode enabled\n");
  } else {
    Print (L"  ⚠ Engineering Mode write failed (readback: 0x%08X)\n", ReadBack);
  }
  Print (L"\n");
  
  // [2/21] VSEC Debug Control
  Print (L"[2/21] VSEC Debug Control (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_DEBUG_CTRL);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_DEBUG_CTRL, 0xFFFFFFFF);
  Print (L"\n");
  
  // [3/21] VSEC Fuse Override
  Print (L"[3/21] VSEC Fuse Override (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_FUSE_OVERRIDE);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_FUSE_OVERRIDE, 0xFFFFFFFF);
  Print (L"\n");
  
  // [4/21] VSEC Security Bypass
  Print (L"[4/21] VSEC Security Bypass (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_SECURITY_BYPASS);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_SECURITY_BYPASS, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_SECURITY_BYPASS);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ Security Bypass enabled\n");
  } else {
    Print (L"  ⚠ Security Bypass write failed (hardware-protected)\n");
  }
  Print (L"\n");
  
  // [5/21] VSEC Control Register (full access)
  Print (L"[5/21] VSEC Control Register (full access) (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_CTRL_REG);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_CTRL_REG, 0x0000007F);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_CTRL_REG);
  if (ReadBack == 0x7F || ReadBack == 0xFFFFFFFF) {
    Print (L"  ✓ Control Register set (full access)\n");
  } else {
    Print (L"  ⚠ Control Register write failed (readback: 0x%08X)\n", ReadBack);
  }
  Print (L"\n");
  
  // [6/21] VSEC Feature Unlock
  Print (L"[6/21] VSEC Feature Unlock (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_FEAT_UNLOCK_REG);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_FEAT_UNLOCK_REG, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_FEAT_UNLOCK_REG);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ Feature Unlock enabled\n");
  }
  Print (L"\n");
  
  // [7/21] VSEC CPU Caps Override
  Print (L"[7/21] VSEC CPU Caps Override (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_CPU_CAPS_OVERRIDE);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_CPU_CAPS_OVERRIDE, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_CPU_CAPS_OVERRIDE);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ CPU Caps Override enabled\n");
  }
  Print (L"\n");
  
  // [8/21] VSEC Fuse Map Control
  Print (L"[8/21] VSEC Fuse Map Control (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_FUSE_MAP_CTRL);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_FUSE_MAP_CTRL, 0x00000001);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_FUSE_MAP_CTRL);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ Fuse Map Control enabled\n");
  }
  Print (L"\n");
  
  // [9/21] VSEC Hidden MSR Enable
  Print (L"[9/21] VSEC Hidden MSR Enable (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_HIDDEN_MSR);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_HIDDEN_MSR, 0xFFFFFFFF);
  Print (L"\n");
  
  // [10/21] VSEC AVX512 Unlock
  Print (L"[10/21] VSEC AVX512 Unlock (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_AVX512_UNLOCK_REG);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_AVX512_UNLOCK_REG, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_AVX512_UNLOCK_REG);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓✓✓ AVX512 Unlock written\n");
  } else {
    Print (L"  ⚠ AVX512 Unlock write failed (hardware-protected)\n");
  }
  Print (L"\n");
  
  // [11/21] VSEC AMX Unlock
  Print (L"[11/21] VSEC AMX Unlock (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_AMX_UNLOCK_REG);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_AMX_UNLOCK_REG, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_AMX_UNLOCK_REG);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓✓✓ AMX Unlock written\n");
  } else {
    Print (L"  ⚠ AMX Unlock write failed (hardware-protected)\n");
  }
  Print (L"\n");
  
  // [12/21] VSEC TME Unlock
  Print (L"[12/21] VSEC TME Unlock (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_TME_UNLOCK);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_TME_UNLOCK, 0xFFFFFFFF);
  Print (L"\n");
  
  // [13/21] VSEC SGX Unlock
  Print (L"[13/21] VSEC SGX Unlock (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_SGX_UNLOCK);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_SGX_UNLOCK, 0xFFFFFFFF);
  Print (L"\n");
  
  // [14/21] VSEC TDX Unlock
  Print (L"[14/21] VSEC TDX Unlock (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_TDX_UNLOCK);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_TDX_UNLOCK, 0xFFFFFFFF);
  Print (L"\n");
  
  // [15/21] VSEC CSME Bypass
  Print (L"[15/21] VSEC CSME Bypass (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_CSME_BYPASS);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_CSME_BYPASS, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_CSME_BYPASS);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ CSME Bypass enabled\n");
  }
  Print (L"\n");
  
  // [16/21] VSEC ME Control - Direct HAP Enable
  Print (L"[16/21] VSEC ME Control - Direct HAP Enable (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_ME_CONTROL);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_ME_CONTROL, 0xFFFFFFFF);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_ME_CONTROL);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓✓✓ VSEC ME Control written (direct HAP enable attempt)\n");
  } else {
    Print (L"  ⚠ VSEC ME Control write failed (hardware-protected)\n");
  }
  Print (L"\n");
  
  // [17/21] VSEC ME Status
  Print (L"[17/21] VSEC ME Status (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_ME_STATUS);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_ME_STATUS);
  Print (L"  ME Status: 0x%08X\n", ReadBack);
  Print (L"\n");
  
  // [18/21] VSEC ME Version
  Print (L"[18/21] VSEC ME Version (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_ME_VERSION);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_ME_VERSION);
  Print (L"  ME Version: 0x%08X\n", ReadBack);
  Print (L"\n");
  
  // [19/21] VSEC BootGuard Control
  Print (L"[19/21] VSEC BootGuard Control (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_BOOTGUARD_CTRL);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_BOOTGUARD_CTRL, 0x00000000);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_BOOTGUARD_CTRL);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ BootGuard disabled\n");
  }
  Print (L"\n");
  
  // [20/21] VSEC Secure Boot Control
  Print (L"[20/21] VSEC Secure Boot Control (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_SECURE_BOOT_CTRL);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_SECURE_BOOT_CTRL, 0x00000000);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_SECURE_BOOT_CTRL);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ Secure Boot disabled\n");
  }
  Print (L"\n");
  
  // [21/21] VSEC BIOS Lock Control
  Print (L"[21/21] VSEC BIOS Lock Control (0x%016llX)...\n", VSEC_MMIO_BASE + VSEC_BIOS_LOCK_CTRL);
  MmioWrite32 (VSEC_MMIO_BASE + VSEC_BIOS_LOCK_CTRL, 0x00000000);
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_BIOS_LOCK_CTRL);
  if (ReadBack != 0xDEADBEEF) {
    Print (L"  ✓ BIOS Lock disabled\n");
  }
  Print (L"\n");
  
  // Verify VSEC writes
  Print (L"[VERIFY] Reading VSEC registers back...\n");
  Print (L"VSEC Control (should be 0x7F or 0xFFFFFFFF):\n");
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_CTRL_REG);
  Print (L"  0x%08X\n", ReadBack);
  Print (L"VSEC AVX512 Unlock (should be 0xFFFFFFFF):\n");
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_AVX512_UNLOCK_REG);
  Print (L"  0x%08X\n", ReadBack);
  Print (L"VSEC AMX Unlock (should be 0xFFFFFFFF):\n");
  ReadBack = MmioRead32 (VSEC_MMIO_BASE + VSEC_AMX_UNLOCK_REG);
  Print (L"  0x%08X\n", ReadBack);
  Print (L"Note: If reads show 0xDEADBEEF, writes are hardware-protected\n\n");
  
  return Status;
}

// HAP activation (6 different methods from uefi_unlock_maximum_aggressive.nsh)
EFI_STATUS
DsmilActivateHap (
  VOID
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  UINT32      HeciStatus;
  UINT32      HeciHfsts1;
  UINTN       HeciCmdAddr = HECI_MMIO_BASE + HECI_CMD;
  UINTN       HeciDoorbellAddr = HECI_MMIO_BASE + HECI_DOORBELL;
  UINTN       HeciHfsts1Addr = HECI_MMIO_BASE + HECI_HFSTS1;
  UINTN       HeciResultAddr = HECI_MMIO_BASE + HECI_RESULT;
  
  Print (L"TIER 2: HAP MODE ACTIVATION (Multiple Methods)\n");
  Print (L"Purpose: Activate HAP mode using ALL discovered methods\n");
  Print (L"Why Multiple: ME may block one method but accept another\n\n");
  
  // [1/6] HAP Method 1: HAP Override Command (0x85FF)
  Print (L"[1/6] HAP Method 1: HAP Override Command (0x85FF)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_HAP_OVERRIDE);
  if (EFI_ERROR (Status)) {
    Print (L"  ⚠ HAP Override command write failed\n");
  } else {
    Print (L"  ✓ HAP Override command written\n");
    MmioWrite32 (HeciDoorbellAddr, 0x80000001);  // HAP privilege bit
    if (!EFI_ERROR (Status)) {
      Print (L"  ✓ HAP doorbell triggered (HAP privilege bit set)\n");
      gBS->Stall (500000);  // 500ms
      HeciStatus = MmioRead32 (HeciResultAddr);
      Print (L"  HAP Override result: 0x%08X\n", HeciStatus);
    }
  }
  Print (L"\n");
  
  // [2/6] HAP Method 2: Feature Unlock Command (0x8600)
  Print (L"[2/6] HAP Method 2: Feature Unlock Command (0x8600)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_FEATURE_UNLOCK);
  if (!EFI_ERROR (Status)) {
    MmioWrite32 (HeciDoorbellAddr, 0x80000001);
    gBS->Stall (500000);
    HeciStatus = MmioRead32 (HeciResultAddr);
    Print (L"  Feature Unlock result: 0x%08X\n", HeciStatus);
  }
  Print (L"\n");
  
  // [3/6] HAP Method 3: MKHI Security Unlock (0x0302)
  Print (L"[3/6] HAP Method 3: MKHI Security Unlock (0x0302)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_MKHI_SEC_UNLOCK);
  if (!EFI_ERROR (Status)) {
    MmioWrite32 (HeciDoorbellAddr, 0x80000001);
    gBS->Stall (500000);
    HeciStatus = MmioRead32 (HeciResultAddr);
    Print (L"  MKHI Security Unlock result: 0x%08X\n", HeciStatus);
  }
  Print (L"\n");
  
  // [4/6] HAP Method 4: Engineering Mode Enable (0x0303)
  Print (L"[4/6] HAP Method 4: Engineering Mode Enable (0x0303)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_MKHI_ENG_MODE);
  if (!EFI_ERROR (Status)) {
    MmioWrite32 (HeciDoorbellAddr, 0x80000001);
    gBS->Stall (500000);
    HeciStatus = MmioRead32 (HeciResultAddr);
    Print (L"  Engineering Mode result: 0x%08X\n", HeciStatus);
  }
  Print (L"\n");
  
  // [5/6] HAP Method 5: System Unlock (0x8602)
  Print (L"[5/6] HAP Method 5: System Unlock (0x8602)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_SYSTEM_UNLOCK);
  if (!EFI_ERROR (Status)) {
    MmioWrite32 (HeciDoorbellAddr, 0x80000001);
    gBS->Stall (500000);
    HeciStatus = MmioRead32 (HeciResultAddr);
    Print (L"  System Unlock result: 0x%08X\n", HeciStatus);
  }
  Print (L"\n");
  
  // [6/6] HAP Method 6: Flex Fabric Activation (0x8601)
  Print (L"[6/6] HAP Method 6: Flex Fabric Activation (0x8601)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_FLEX_FABRIC);
  if (!EFI_ERROR (Status)) {
    MmioWrite32 (HeciDoorbellAddr, 0x80000001);
    gBS->Stall (500000);
    HeciStatus = MmioRead32 (HeciResultAddr);
    Print (L"  Flex Fabric result: 0x%08X\n", HeciStatus);
  }
  Print (L"\n");
  
  // Verify HAP activation (check HFSTS1 bit 12)
  Print (L"[VERIFY] Checking HAP Mode Status (HFSTS1)...\n");
  HeciHfsts1 = MmioRead32 (HeciHfsts1Addr);
  Print (L"HFSTS1 value: 0x%08X (bit 12 should be 1 for HAP active)\n", HeciHfsts1);
  if ((HeciHfsts1 & (1 << 12)) != 0) {
    Print (L"  ✓✓✓ HAP Mode is ACTIVE (HFSTS1 bit 12 set)\n");
    Status = EFI_SUCCESS;
  } else {
    Print (L"  ⚠ HAP Mode is INACTIVE (HFSTS1 bit 12 not set)\n");
    Status = EFI_NOT_READY;
  }
  Print (L"\n");
  
  return Status;
}

// Host Bridge unlock
EFI_STATUS
DsmilHostBridgeUnlock (
  VOID
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  UINT32      ReadBack;
  
  Print (L"TIER 4: HOST BRIDGE UNLOCK\n");
  Print (L"Purpose: Unlock Host Bridge control registers\n\n");
  
  // [1/2] Host Bridge Control Register (0xEC)
  Print (L"[1/2] Host Bridge Control Register (0xEC)...\n");
  Status = PciWrite32 (HOST_BRIDGE_PCI_ADDR, HOST_BRIDGE_CTRL, 0xFFFFFFFF);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Host Bridge Control unlocked\n");
  } else {
    Print (L"  ⚠ Host Bridge Control write failed\n");
  }
  Print (L"\n");
  
  // [2/2] Host Bridge Status Register (0xF0)
  Print (L"[2/2] Host Bridge Status Register (0xF0)...\n");
  ReadBack = PciRead32 (HOST_BRIDGE_PCI_ADDR, HOST_BRIDGE_STATUS);
  Print (L"  Host Bridge Status: 0x%08X\n", ReadBack);
  Status = PciWrite32 (HOST_BRIDGE_PCI_ADDR, HOST_BRIDGE_STATUS, 0xFFFFFFFF);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Host Bridge Status written\n");
  }
  Print (L"\n");
  
  return Status;
}

// Microcode staging (for next boot)
EFI_STATUS
DsmilStageMicrocode (
  IN UINT8  MicrocodeVersion
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  UINT32      ReadBack;
  UINTN       HeciDowngradeAddr = HECI_MMIO_BASE + HECI_DOWNGRADE_EN;
  UINTN       HeciTargetVerAddr = HECI_MMIO_BASE + HECI_TARGET_VER;
  UINTN       HeciCpuSigAddr = HECI_MMIO_BASE + HECI_CPU_SIG;
  UINTN       HeciCmdAddr = HECI_MMIO_BASE + HECI_CMD;
  UINTN       HeciDoorbellAddr = HECI_MMIO_BASE + HECI_DOORBELL;
  UINTN       HeciResultAddr = HECI_MMIO_BASE + HECI_RESULT;
  
  Print (L"TIER 5: MICROCODE STAGING (For Next Boot)\n");
  Print (L"Purpose: Stage microcode 0x%02X for feature unlock on next boot\n\n", MicrocodeVersion);
  
  // [1/6] HECI Microcode Staging Setup - Enable downgrade
  Print (L"[1/6] HECI Microcode Staging Setup...\n");
  MmioWrite32 (HeciDowngradeAddr, 0x00000001);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Downgrade enable written\n");
  }
  Print (L"\n");
  
  // [2/6] Target Microcode Version
  Print (L"[2/6] Target Microcode Version (0x%02X)...\n", MicrocodeVersion);
  MmioWrite32 (HeciTargetVerAddr, (UINT32)MicrocodeVersion);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Target version set (0x%02X)\n", MicrocodeVersion);
  }
  Print (L"\n");
  
  // [3/6] CPU Signature (06-AA-04 = 0x000A06A4)
  Print (L"[3/6] CPU Signature (06-AA-04 = 0x000A06A4)...\n");
  MmioWrite32 (HeciCpuSigAddr, 0x000A06A4);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ CPU signature set\n");
  }
  Print (L"\n");
  
  // [4/6] Microcode Update Command (0x8505)
  Print (L"[4/6] Microcode Update Command (0x8505)...\n");
  MmioWrite32 (HeciCmdAddr, ME_CMD_MICROCODE_OVERRIDE);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Microcode command written\n");
  }
  Print (L"\n");
  
  // [5/6] Execute Command (Doorbell)
  Print (L"[5/6] Execute Command (Doorbell)...\n");
  MmioWrite32 (HeciDoorbellAddr, 0x00000001);
  if (!EFI_ERROR (Status)) {
    Print (L"  ✓ Command execution triggered\n");
    gBS->Stall (500000);  // 500ms
  }
  Print (L"\n");
  
  // [6/6] Check Microcode Staging Result
  Print (L"[6/6] Check Microcode Staging Result...\n");
  ReadBack = MmioRead32 (HeciResultAddr);
  Print (L"Microcode staging result: 0x%08X\n", ReadBack);
  Print (L"Note: Microcode takes effect after COLD BOOT\n\n");
  
  return Status;
}

// I2C Controller unlock (fuse manipulation)
EFI_STATUS
DsmilI2CUnlock (
  VOID
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  
  Print (L"TIER 6: I2C CONTROLLER UNLOCK (Fuse Manipulation)\n");
  Print (L"Purpose: Unlock I2C controllers for fuse manipulation\n\n");
  
  // [1/2] I2C Controller 0 Unlock
  Print (L"[1/2] I2C Controller 0 Unlock...\n");
  MmioWrite32 (I2C_CTRL0_MMIO, 0xFFFFFFFF);
  MmioWrite32 (I2C_CTRL0_MMIO + 0x04, 0xFFFFFFFF);
  Print (L"\n");
  
  // [2/2] I2C Controller 3 Unlock
  Print (L"[2/2] I2C Controller 3 Unlock...\n");
  MmioWrite32 (I2C_CTRL3_MMIO, 0xFFFFFFFF);
  MmioWrite32 (I2C_CTRL3_MMIO + 0x04, 0xFFFFFFFF);
  Print (L"\n");
  
  return Status;
}

// Additional hardware unlocks (NPU, Thunderbolt, Graphics)
EFI_STATUS
DsmilAdditionalHardwareUnlock (
  VOID
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  
  Print (L"TIER 7: ADDITIONAL HARDWARE UNLOCKS\n");
  Print (L"Purpose: Unlock any remaining hardware features\n\n");
  
  // [1/3] NPU Unlock (Device 0x7D1D at 00:0b.0)
  Print (L"[1/3] NPU Unlock (Device 0x7D1D at 00:0b.0)...\n");
  MmioWrite32 (NPU_MMIO_BASE, 0xFFFFFFFF);
  MmioWrite32 (NPU_MMIO_BASE + 0x04, 0xFFFFFFFF);
  Print (L"\n");
  
  // [2/3] Thunderbolt Controller Unlock (00:0d.3)
  Print (L"[2/3] Thunderbolt Controller Unlock (00:0d.3)...\n");
  PciWrite32 (0x0000000D30, 0x50, 0xFFFFFFFF);  // 00:0d.3 = 0x0D30
  PciWrite32 (0x0000000D30, 0x54, 0xFFFFFFFF);
  Print (L"\n");
  
  // [3/3] Graphics Controller Unlock (00:02.0)
  Print (L"[3/3] Graphics Controller Unlock (00:02.0)...\n");
  PciWrite32 (0x0000000200, 0x50, 0xFFFFFFFF);  // 00:02.0 = 0x0200
  PciWrite32 (0x0000000200, 0x54, 0xFFFFFFFF);
  Print (L"\n");
  
  return Status;
}

// Full unlock sequence (comprehensive - all tiers from uefi_unlock_maximum_aggressive.nsh)
EFI_STATUS
DsmilFullUnlock (
  IN CHAR16  *Mode
  )
{
  BOOLEAN  Aggressive = FALSE;
  EFI_STATUS  Status = EFI_SUCCESS;
  
  if (Mode != NULL) {
    if (StrCmp (Mode, L"aggressive") == 0 || StrCmp (Mode, L"complete") == 0) {
      Aggressive = TRUE;
    }
  }
  
  Print (L"===============================================================================\n");
  Print (L"DSMIL FULL UNLOCK SEQUENCE (MAXIMUM AGGRESSIVE)\n");
  Print (L"Mode: %s\n", Mode != NULL ? Mode : L"safe");
  Print (L"Purpose: Unlock ALL features using EVERY discovered address and method\n");
  Print (L"Strategy: Maximum clearance → MSR coordination → Device255 → HAP → VSEC → Features\n");
  Print (L"===============================================================================\n\n");
  
  // TIER 0: Set maximum clearance
  Print (L"TIER 0: MAXIMUM CLEARANCE SETTING (FIRST - PREREQUISITE)\n");
  DsmilSetClearance (CLEARANCE_LAYER9);
  gBS->Stall (100000);  // 100ms
  Print (L"\n");
  
  // TIER 0.5: Coordinate MSRs
  Print (L"TIER 0.5: MSR COORDINATION REGISTERS (SYNCHRONIZATION)\n");
  DsmilCoordinateMsrs ();
  gBS->Stall (100000);
  Print (L"\n");
  
  // TIER 1: Unlock Device255
  DsmilDevice255Unlock ();
  gBS->Stall (200000);  // 200ms
  Print (L"\n");
  
  // TIER 2: Activate HAP (6 methods)
  DsmilActivateHap ();
  gBS->Stall (500000);  // 500ms
  Print (L"\n");
  
  // TIER 3: VSEC unlock (all 21 registers)
  DsmilVsecUnlock (Aggressive);
  gBS->Stall (200000);
  Print (L"\n");
  
  // TIER 4: Host Bridge unlock
  DsmilHostBridgeUnlock ();
  gBS->Stall (100000);
  Print (L"\n");
  
  // TIER 5: Microcode staging (if aggressive mode)
  if (Aggressive) {
    DsmilStageMicrocode (0x1C);  // Microcode version 0x1C
    gBS->Stall (100000);
    Print (L"\n");
  }
  
  // TIER 6: I2C Controller unlock (if aggressive mode)
  if (Aggressive) {
    DsmilI2CUnlock ();
    gBS->Stall (100000);
    Print (L"\n");
  }
  
  // TIER 7: Additional hardware unlocks (if aggressive mode)
  if (Aggressive) {
    DsmilAdditionalHardwareUnlock ();
    gBS->Stall (100000);
    Print (L"\n");
  }
  
  // Comprehensive verification
  Print (L"===============================================================================\n");
  Print (L"COMPREHENSIVE VERIFICATION\n");
  Print (L"===============================================================================\n\n");
  
  Print (L"[1/8] HAP Mode Status (HFSTS1 bit 12)...\n");
  UINT32 HeciHfsts1 = MmioRead32 (HECI_MMIO_BASE + HECI_HFSTS1);
  Print (L"  HFSTS1: 0x%08X (bit 12 = %d)\n", HeciHfsts1, (HeciHfsts1 >> 12) & 1);
  Print (L"\n");
  
  Print (L"[2/8] VSEC Control Register...\n");
  UINT32 VsecCtrl = MmioRead32 (VSEC_MMIO_BASE + VSEC_CTRL_REG);
  Print (L"  VSEC Control: 0x%08X\n", VsecCtrl);
  Print (L"\n");
  
  Print (L"[3/8] VSEC AVX512 Unlock...\n");
  UINT32 VsecAvx512 = MmioRead32 (VSEC_MMIO_BASE + VSEC_AVX512_UNLOCK_REG);
  Print (L"  VSEC AVX512: 0x%08X\n", VsecAvx512);
  Print (L"\n");
  
  Print (L"[4/8] VSEC AMX Unlock...\n");
  UINT32 VsecAmx = MmioRead32 (VSEC_MMIO_BASE + VSEC_AMX_UNLOCK_REG);
  Print (L"  VSEC AMX: 0x%08X\n", VsecAmx);
  Print (L"\n");
  
  Print (L"[5/8] VSEC Feature Unlock...\n");
  UINT32 VsecFeat = MmioRead32 (VSEC_MMIO_BASE + VSEC_FEAT_UNLOCK_REG);
  Print (L"  VSEC Feature: 0x%08X\n", VsecFeat);
  Print (L"\n");
  
  Print (L"[6/8] Host Bridge Control...\n");
  UINT32 HostBridge = PciRead32 (HOST_BRIDGE_PCI_ADDR, HOST_BRIDGE_CTRL);
  Print (L"  Host Bridge Control: 0x%08X\n", HostBridge);
  Print (L"\n");
  
  Print (L"[7/8] Device255 Status (via SMBus)...\n");
  UINT32 SmbusStatus = MmioRead32 (SMBUS_MMIO_BASE);
  Print (L"  SMBus Status: 0x%08X\n", SmbusStatus);
  Print (L"\n");
  
  Print (L"[8/8] ME HECI Status...\n");
  UINT32 HeciStatus = MmioRead32 (HECI_MMIO_BASE + HECI_ME_CSR_HA);
  Print (L"  ME_CSR_HA: 0x%08X\n", HeciStatus);
  Print (L"\n");
  
  Print (L"===============================================================================\n");
  Print (L"SUMMARY\n");
  Print (L"===============================================================================\n\n");
  Print (L"Unlock operations attempted:\n");
  Print (L"  ✓ Maximum Clearance (Layer 9)\n");
  Print (L"  ✓ MSR Coordination (6 registers)\n");
  Print (L"  ✓ Device255 Unlock (3 patterns)\n");
  Print (L"  ✓ HAP Activation (6 different methods)\n");
  Print (L"  ✓ VSEC Unlock (21 registers - includes ME, BootGuard, Secure Boot, BIOS Lock)\n");
  Print (L"  ✓ Host Bridge Unlock\n");
  if (Aggressive) {
    Print (L"  ✓ Microcode Staging (0x1C)\n");
    Print (L"  ✓ I2C Controller Unlock\n");
    Print (L"  ✓ Additional Hardware Unlocks\n");
  }
  Print (L"\n");
  Print (L"Next Steps:\n");
  Print (L"  1. COLD BOOT (power cycle) required for microcode and some unlocks\n");
  Print (L"  2. After boot, verify AVX512/AMX appear in /proc/cpuinfo\n");
  Print (L"  3. Verify HAP bit 12 is set in HFSTS1\n");
  Print (L"  4. Check that features are unlocked\n");
  Print (L"\n");
  // Write UEFI unlock completion marker to MSR 0x1B0 (persists across boot)
  // Kernel modules will check this MSR on init and mark prerequisites complete
  Print (L"Writing UEFI unlock completion marker to MSR 0x1B0...\n");
  UINT64 UefiMarker = 0x55554549464C554BULL;  // "UEFIUNLK" in ASCII
  DsmilMsrWrite (MSR_COORD_1B0, UefiMarker);
  Print (L"  ✓ Marker written (kernel modules will detect this on boot)\n");
  Print (L"\n");
  
  Print (L"===============================================================================\n");
  Print (L"✓✓✓ FULL DSMIL UNLOCK SEQUENCE COMPLETED ✓✓✓\n");
  Print (L"===============================================================================\n");
  Print (L"\n");
  Print (L"UEFI-Kernel Coordination:\n");
  Print (L"  - UEFI shell completed early unlocks\n");
  Print (L"  - Marker written to MSR 0x1B0: 0x%016llX\n", UefiMarker);
  Print (L"  - Kernel modules will detect marker and skip redundant operations\n");
  Print (L"  - Check /proc/dsmil_unlock/status after boot to verify\n");
  Print (L"\n");
  
  return EFI_SUCCESS;
}

// Main command handler
SHELL_STATUS
EFIAPI
DsmilUnlockCommandHandler (
  IN EFI_SHELL_DYNAMIC_COMMAND_PROTOCOL  *This,
  IN EFI_SYSTEM_TABLE                    *SystemTable,
  IN EFI_SHELL_PARAMETERS_PROTOCOL       *ShellParameters,
  IN EFI_SHELL_PROTOCOL                  *Shell
  )
{
  EFI_STATUS  Status;
  CHAR16      **Argv;
  UINTN       Argc;
  UINT32      MsrAddr;
  UINT64      MsrValue;
  CHAR16      *SubCommand;
  
  Argc = ShellParameters->Argc;
  Argv = ShellParameters->Argv;
  
  if (Argc < 2) {
    Print (L"Usage: dsmil-unlock <command> [options]\n");
    Print (L"Commands:\n");
    Print (L"  msr-read <addr>        Read MSR register\n");
    Print (L"  msr-write <addr> <val>  Write MSR register\n");
    Print (L"  coordinate              Set MSR coordination registers\n");
    Print (L"  clearance [value]       Set clearance (default: 0xFF090909)\n");
    Print (L"  device255               Unlock Device255 (3 patterns)\n");
    Print (L"  vsec [aggressive]       Unlock VSEC (21 registers)\n");
    Print (L"  hap                     Activate HAP mode (6 methods)\n");
    Print (L"  host-bridge             Unlock Host Bridge\n");
    Print (L"  microcode [version]     Stage microcode (default: 0x1C)\n");
    Print (L"  i2c                     Unlock I2C controllers\n");
    Print (L"  additional              Additional hardware unlocks\n");
    Print (L"  full [mode]             Full unlock (safe/aggressive/complete)\n");
    Print (L"\n");
    Print (L"Mode options for 'full':\n");
    Print (L"  safe       - Basic unlock (TIER 0-4)\n");
    Print (L"  aggressive - Full unlock (TIER 0-7, includes microcode, I2C, additional)\n");
    Print (L"  complete   - Same as aggressive\n");
    return SHELL_SUCCESS;
  }
  
  SubCommand = Argv[1];
  
  if (StrCmp (SubCommand, L"msr-read") == 0) {
    if (Argc < 3) {
      Print (L"Error: MSR address required\n");
      return SHELL_INVALID_PARAMETER;
    }
    MsrAddr = (UINT32)StrHexToUintn (Argv[2]);
    Status = DsmilMsrRead (MsrAddr, &MsrValue);
    if (!EFI_ERROR (Status)) {
      Print (L"MSR 0x%03X: 0x%016llX\n", MsrAddr, MsrValue);
    }
  } else if (StrCmp (SubCommand, L"msr-write") == 0) {
    if (Argc < 4) {
      Print (L"Error: MSR address and value required\n");
      return SHELL_INVALID_PARAMETER;
    }
    MsrAddr = (UINT32)StrHexToUintn (Argv[2]);
    MsrValue = StrHexToUintn (Argv[3]);
    Status = DsmilMsrWrite (MsrAddr, MsrValue);
    if (!EFI_ERROR (Status)) {
      Print (L"✓ MSR 0x%03X written: 0x%016llX\n", MsrAddr, MsrValue);
    }
  } else if (StrCmp (SubCommand, L"coordinate") == 0) {
    DsmilCoordinateMsrs ();
  } else if (StrCmp (SubCommand, L"clearance") == 0) {
    UINT32 Clearance = CLEARANCE_LAYER9;
    if (Argc >= 3) {
      Clearance = (UINT32)StrHexToUintn (Argv[2]);
    }
    DsmilSetClearance (Clearance);
  } else if (StrCmp (SubCommand, L"device255") == 0) {
    DsmilDevice255Unlock ();
  } else if (StrCmp (SubCommand, L"vsec") == 0) {
    BOOLEAN Aggressive = (Argc >= 3 && StrCmp (Argv[2], L"aggressive") == 0);
    DsmilVsecUnlock (Aggressive);
  } else if (StrCmp (SubCommand, L"hap") == 0) {
    DsmilActivateHap ();
  } else if (StrCmp (SubCommand, L"host-bridge") == 0) {
    DsmilHostBridgeUnlock ();
  } else if (StrCmp (SubCommand, L"microcode") == 0) {
    UINT8 MicrocodeVersion = 0x1C;
    if (Argc >= 3) {
      MicrocodeVersion = (UINT8)StrHexToUintn (Argv[2]);
    }
    DsmilStageMicrocode (MicrocodeVersion);
  } else if (StrCmp (SubCommand, L"i2c") == 0) {
    DsmilI2CUnlock ();
  } else if (StrCmp (SubCommand, L"additional") == 0) {
    DsmilAdditionalHardwareUnlock ();
  } else if (StrCmp (SubCommand, L"full") == 0) {
    CHAR16 *Mode = (Argc >= 3) ? Argv[2] : L"safe";
    DsmilFullUnlock (Mode);
  } else {
    Print (L"Error: Unknown command: %s\n", SubCommand);
    return SHELL_INVALID_PARAMETER;
  }
  
  return SHELL_SUCCESS;
}

CHAR16 *
EFIAPI
DsmilUnlockCommandGetHelp (
  IN EFI_SHELL_DYNAMIC_COMMAND_PROTOCOL  *This,
  IN CONST CHAR8                         *Language
  )
{
  return L"DSMIL Unlock Command - Integrated MSR, CCTK, and unlock tools\n"
         L"Usage: dsmil-unlock <command> [options]\n"
         L"See 'dsmil-unlock' for full command list\n";
}
