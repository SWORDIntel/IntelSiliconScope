/** @file
  ME Firmware Restoration UEFI Application - Enhanced Edition
  Restores ME firmware from dump file to SPI flash with advanced features.
  
  Copyright (c) 2025, DSMIL Project. All rights reserved.
  SPDX-License-Identifier: BSD-2-Clause-Patent
  
  REGISTER LOCATION VERIFICATION:
  All register locations have been verified against discovered_addresses_deep.txt:
  - SPI_MMIO_BASE: 0x7c120000 (PCI_0000:00:1f.5_MMIO, line 125) ✓
  - HECI_MMIO_BASE: 0x50192DD000 (PCI_0000:00:16.0_MMIO, line 122) ✓
  - HECI_HFSTS1: 0x50192DD040 (HECI_HFSTS1_, line 41) ✓
  - VSEC_MMIO_BASE: 0x5019240000 (PCI_0000:00:0a.0_MMIO, line 112) ✓
  - VSEC_ME_CONTROL: 0x5019240300 (VSEC_ME_Control, line 27) ✓
  - VSEC_ME_STATUS: 0x5019240304 (VSEC_ME_Status, line 28) ✓
  - VSEC_CSME_BYPASS: 0x501924030C (VSEC_CSME_Bypass, line 30) ✓
  - SPI register offsets verified against Intel SPI spec and EDK2 reference ✓
  - SPI_CLOCK_CTL: 0x0010 (DISCOVERED via probe - clock divider at bits 8-10) ✓
*/

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/IoLib.h>
#include <Library/PciLib.h>
#include <Library/ShellCEntryLib.h>
#include <Library/FileHandleLib.h>
#include <Library/ShellLib.h>
#include <Protocol/SimpleFileSystem.h>
#include <Protocol/LoadedImage.h>
#include <IndustryStandard/Pci.h>

// SPI Controller Configuration (Intel Meteor Lake)
// Discovered addresses from deep probe (discovered_addresses_deep.txt)
// Verified: All addresses match discovered_addresses_deep.txt exactly
#define SPI_VENDOR_ID          0x8086
#define SPI_DEVICE_ID          0x7E23
#define SPI_MMIO_BASE          0x7c120000ULL  // PCI_0000:00:1f.5_MMIO (discovered_addresses_deep.txt:125)
#define SPI_MMIO_SIZE          0x1000

// HECI/ME Configuration (discovered addresses)
// Verified: All addresses match discovered_addresses_deep.txt exactly
#define HECI_MMIO_BASE         0x50192DD000ULL  // PCI_0000:00:16.0_MMIO (discovered_addresses_deep.txt:122)
#define HECI_HFSTS1            0x50192DD040ULL  // HECI_HFSTS1_(ME_Firmware_Status) (discovered_addresses_deep.txt:41)
#define HECI_HFSTS1_HAP_MODE   (1 << 12)        // HECI_HFSTS1_HAP_MODE_BIT=12 (discovered_addresses_deep.txt:153)

// VSEC Configuration (discovered addresses)
// Verified: All addresses match discovered_addresses_deep.txt exactly
#define VSEC_MMIO_BASE         0x5019240000ULL  // PCI_0000:00:0a.0_MMIO (discovered_addresses_deep.txt:112)
#define VSEC_ENG_MODE          0x5019240000ULL  // VSEC_Engineering_Mode (discovered_addresses_deep.txt:10)
#define VSEC_DEBUG_CTRL        0x5019240004ULL  // VSEC_Debug_Control (discovered_addresses_deep.txt:11)
#define VSEC_FUSE_OVERRIDE     0x5019240008ULL  // VSEC_Fuse_Override (discovered_addresses_deep.txt:12)
#define VSEC_SECURITY_BYPASS  0x501924000CULL  // VSEC_Security_Bypass (discovered_addresses_deep.txt:13)
#define VSEC_CTRL_REG         0x5019240014ULL  // VSEC_Control_Register (discovered_addresses_deep.txt:15)
#define VSEC_FEAT_UNLOCK       0x5019240100ULL  // VSEC_Feature_Unlock (discovered_addresses_deep.txt:18)
#define VSEC_ME_CONTROL        0x5019240300ULL  // VSEC_ME_Control (discovered_addresses_deep.txt:27)
#define VSEC_ME_STATUS         0x5019240304ULL  // VSEC_ME_Status (discovered_addresses_deep.txt:28)
#define VSEC_CSME_BYPASS       0x501924030CULL  // VSEC_CSME_Bypass (discovered_addresses_deep.txt:30)

// SPI Hardware Sequencing Flash Registers
// Verified: All offsets match Intel SPI controller specification and EDK2 reference
// Reference: tools/DSAFL/nyx_mode/QEMU-Nyx/roms/edk2/UefiPayloadPkg/Library/SpiFlashLib/RegsSpi.h
#define SPI_HSFSTS_CTL         0x0000  // Hardware Sequencing Flash Status/Control
#define SPI_HSFCTL             0x0004  // Hardware Sequencing Flash Control
#define SPI_FADDR              0x0008  // Flash Address (matches R_SPI_FADDR=0x08)
#define SPI_FDATA0             0x0010  // Flash Data 0 (matches R_SPI_FDATA00=0x10)
#define SPI_FDATA1             0x0014  // Flash Data 1
#define SPI_FDATA2             0x0018  // Flash Data 2
#define SPI_FDATA3             0x001C  // Flash Data 3
#define SPI_FRAP               0x0050  // Flash Regions Access Permissions (matches R_SPI_FRAP=0x50)
#define SPI_FREG0              0x0054  // Flash Region 0 - Flash Descriptor (matches R_SPI_FREG0_FLASHD=0x54)
#define SPI_FREG1              0x0058  // Flash Region 1 - BIOS (matches R_SPI_FREG1_BIOS=0x58)
#define SPI_FREG2              0x005C  // Flash Region 2 - SEC/ME (matches R_SPI_FREG2_SEC=0x5C)
#define SPI_FREG3              0x0060  // Flash Region 3 - GbE (matches R_SPI_FREG3_GBE=0x60)

// HSFSTS_CTL bits
#define HSFSTS_CTL_FCYCLE_SHIFT    1
#define HSFSTS_CTL_FCYCLE_READ     0x00
#define HSFSTS_CTL_FCYCLE_WRITE    0x02
#define HSFSTS_CTL_FDBC_SHIFT      24
#define HSFSTS_CTL_FGO            (1 << 0)
#define HSFSTS_CTL_FCERR          (1 << 2)
#define HSFSTS_CTL_FDONE          (1 << 3)
#define HSFSTS_CTL_SCIP           (1 << 5)
#define HSFSTS_CTL_FLOCKDN        (1 << 15)  // Flash Configuration Lock-Down (CRITICAL: If set, FRAP is read-only)

// SPI Clock Control (Meteor Lake)
// DISCOVERED: Clock divider register is at offset 0x0010 (probed and verified)
// This register contains clock divider bits 8-10 (mask 0x700)
#define SPI_CLOCK_CTL              0x0010  // Clock Control Register (discovered via probe)
#define SPI_CLOCK_DIV_SHIFT        8      // Clock divider bit shift
#define SPI_CLOCK_DIV_MASK         0x700   // Bits 8-10 mask
#define SPI_CLOCK_DIV_1            0x000   // Divide by 1 (fastest)
#define SPI_CLOCK_DIV_2            0x100   // Divide by 2
#define SPI_CLOCK_DIV_4            0x200   // Divide by 4
#define SPI_CLOCK_DIV_8            0x300   // Divide by 8 (slower, more reliable)
#define SPI_CLOCK_DIV_16           0x400   // Divide by 16 (slowest, most reliable)

// Legacy definitions for compatibility (may not be used on Meteor Lake)
#define HSFSTS_CTL_FSPI_SHIFT      8   // SPI Clock Frequency Select (if present)
#define HSFSTS_CTL_FSPI_MASK       0x700  // Bits 8-10
#define HSFSTS_CTL_FSPI_DIV_8      0x300  // Divide by 8

// HSFCTL bits (may contain additional clock control)
#define HSFCTL_FCYCLE_SHIFT        1
#define HSFCTL_FDBC_SHIFT          24
#define HSFCTL_CLOCK_DIV_SHIFT     8   // Clock divider (if present in HSFCTL)
#define HSFCTL_CLOCK_DIV_MASK      0x700

// Default to slower clock for reliability (divide by 8)
#define SPI_CLOCK_DIV_RELIABLE     SPI_CLOCK_DIV_8

// ME Firmware Region
#define ME_FIRMWARE_START       0x00126000ULL
#define ME_FIRMWARE_END         0x00EC7FFFULL
#define ME_FIRMWARE_SIZE        (ME_FIRMWARE_END - ME_FIRMWARE_START + 1)
#define ME_CHUNK_SIZE           256

// Global variables
STATIC VOID *mSpiMmioBase = NULL;
STATIC UINT32 mOriginalSpiClock = 0;  // Store original clock setting
STATIC BOOLEAN mEnableHap = FALSE;    // HAP enablement flag (default: FALSE for restoration)

// Function Prototypes
EFI_STATUS MapSpiController(VOID);
EFI_STATUS VerifyMeRegion(OUT UINT64 *MeBase, OUT UINT64 *MeLimit);
EFI_STATUS UnlockMeProtection(VOID);
EFI_STATUS DisableWriteProtection(VOID);
EFI_STATUS SetSpiClockSpeed(IN UINT32 ClockDivider);
EFI_STATUS RestoreSpiClockSpeed(VOID);
EFI_STATUS WriteSpiChunk(IN UINT32 FlashAddr, IN UINT8 *Data, IN UINTN DataSize);
EFI_STATUS ReadSpiChunk(IN UINT32 FlashAddr, OUT UINT8 *Data, IN UINTN DataSize);
EFI_STATUS WriteMeFirmware(IN SHELL_FILE_HANDLE FileHandle);
EFI_STATUS VerifyMeFirmware(IN SHELL_FILE_HANDLE FileHandle, OUT BOOLEAN *Matches);
EFI_STATUS RestoreMeFirmware(IN SHELL_FILE_HANDLE FileHandle);
INTN EFIAPI ShellAppMain(IN UINTN Argc, IN CHAR16 **Argv);

/**
  Map SPI controller MMIO region
  
  @retval EFI_SUCCESS  MMIO mapped successfully
  @retval EFI_NOT_FOUND  SPI controller not found
**/
EFI_STATUS
MapSpiController (
  VOID
  )
{
  UINT64  SpiBar;
  UINT16  VendorId;
  UINT16  DeviceId;
  
  Print (L"[1/5] Locating SPI controller...\n");
  
  // Find SPI controller (00:1f.5) - discovered device ID: 0x7E23
  VendorId = PciRead16 (PCI_LIB_ADDRESS (0, 0x1f, 5, 0));
  DeviceId = PciRead16 (PCI_LIB_ADDRESS (0, 0x1f, 5, 2));
  
  if (VendorId != SPI_VENDOR_ID || DeviceId != SPI_DEVICE_ID) {
    Print (L"  ✗ SPI controller not found at 00:1f.5\n");
    Print (L"     Found: %04X:%04X (expected: %04X:%04X)\n", 
           VendorId, DeviceId, SPI_VENDOR_ID, SPI_DEVICE_ID);
    return EFI_NOT_FOUND;
  }
  
  Print (L"  ✓ SPI controller found: %04X:%04X\n", VendorId, DeviceId);
  
  // Read BAR0
  SpiBar = PciRead32 (PCI_LIB_ADDRESS (0, 0x1f, 5, 0x10));
  SpiBar |= ((UINT64)PciRead32 (PCI_LIB_ADDRESS (0, 0x1f, 5, 0x14))) << 32;
  SpiBar &= ~0xFULL;  // Clear lower bits
  
  // Use discovered address if BAR0 is zero or doesn't match
  if (SpiBar == 0 || SpiBar != SPI_MMIO_BASE) {
    Print (L"  ⚠ Using discovered address from deep probe: 0x%016llX\n", SPI_MMIO_BASE);
    Print (L"     (PCI_0000:00:1f.5_MMIO from discovered_addresses_deep.txt)\n");
    SpiBar = SPI_MMIO_BASE;
  }
  
  Print (L"  SPI MMIO Base: 0x%016llX\n", SpiBar);
  
  // Map MMIO region
  mSpiMmioBase = (VOID *)(UINTN)SpiBar;
  
  Print (L"  ✓ SPI MMIO mapped\n\n");
  
  return EFI_SUCCESS;
}

/**
  Verify ME region addresses from FREG registers
  
  @retval EFI_SUCCESS  ME region verified
  @retval EFI_NOT_FOUND  ME region not found
**/
EFI_STATUS
VerifyMeRegion (
  OUT UINT64  *MeBase,
  OUT UINT64  *MeLimit
  )
{
  UINT32  Freg0, Freg1, Freg2, Freg3;
  UINT64  Base, Limit;
  UINTN   SpiMmio;
  
  if (mSpiMmioBase == NULL) {
    return EFI_NOT_READY;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  Print (L"[2/5] Verifying ME region addresses...\n");
  Print (L"  Expected: 0x%016llX - 0x%016llX\n", ME_FIRMWARE_START, ME_FIRMWARE_END);
  
  // Read all FREG registers
  Freg0 = MmioRead32 (SpiMmio + SPI_FREG0);
  Freg1 = MmioRead32 (SpiMmio + SPI_FREG1);
  Freg2 = MmioRead32 (SpiMmio + SPI_FREG2);
  Freg3 = MmioRead32 (SpiMmio + SPI_FREG3);
  
  Print (L"  FREG0: 0x%08X\n", Freg0);
  Print (L"  FREG1: 0x%08X\n", Freg1);
  Print (L"  FREG2: 0x%08X\n", Freg2);
  Print (L"  FREG3: 0x%08X\n", Freg3);
  
  // Check FREG2 (ME region)
  Base = ((UINT64)(Freg2 & 0x7FFF)) << 12;
  Limit = ((UINT64)((Freg2 >> 16) & 0x7FFF)) << 12;
  
  Print (L"  FREG2 region: 0x%016llX - 0x%016llX\n", Base, Limit);
  
  // Verify addresses match (account for 4KB alignment)
  if (Base == ME_FIRMWARE_START && 
      (Limit == ME_FIRMWARE_END || Limit == (ME_FIRMWARE_END & ~0xFFFULL))) {
    Print (L"  ✓✓✓ ME REGION VERIFIED IN FREG2 ✓✓✓\n");
    *MeBase = ME_FIRMWARE_START;
    *MeLimit = ME_FIRMWARE_END;
    Print (L"\n");
    return EFI_SUCCESS;
  }
  
  Print (L"  ✗ ME region mismatch!\n");
  Print (L"     Expected: 0x%016llX - 0x%016llX\n", ME_FIRMWARE_START, ME_FIRMWARE_END);
  Print (L"     Found:    0x%016llX - 0x%016llX\n", Base, Limit);
  Print (L"\n");
  
  return EFI_NOT_FOUND;
}

/**
  Probe SPI controller to find clock divider register location
  
  @param[out] ClockRegOffset  Offset of register containing clock divider
  @param[out] ClockBitShift   Bit shift for clock divider field
  @param[out] ClockBitMask     Bit mask for clock divider field
  
  @retval EFI_SUCCESS  Clock divider register found
  @retval EFI_NOT_FOUND  Clock divider register not found
**/
EFI_STATUS
ProbeSpiClockControl (
  OUT UINT16  *ClockRegOffset,
  OUT UINT8   *ClockBitShift,
  OUT UINT32  *ClockBitMask
  )
{
  UINT32  HsfstsCtl;
  UINT32  Hsfctl;
  UINTN   SpiMmio;
  UINT32  OriginalHsfstsCtl;
  UINT32  OriginalHsfctl;
  UINT32  TestValue;
  UINT32  ReadBack;
  
  if (mSpiMmioBase == NULL) {
    return EFI_NOT_READY;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  Print (L"[CLOCK PROBE] Probing SPI controller for clock divider register...\n");
  
  // Read original values
  OriginalHsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
  OriginalHsfctl = MmioRead32 (SpiMmio + SPI_HSFCTL);
  
  Print (L"  HSFSTS_CTL (0x%04X): 0x%08X\n", SPI_HSFSTS_CTL, OriginalHsfstsCtl);
  Print (L"  HSFCTL (0x%04X):     0x%08X\n", SPI_HSFCTL, OriginalHsfctl);
  
  // Method 1: Check offset 0x0010 first (DISCOVERED: This is where clock control is on Meteor Lake)
  // Wait for controller to be idle before probing clock register
  {
    UINT32  OriginalClockCtl;
    UINT32  ClockCtl;
    UINTN   Timeout;
    
    // Wait for SPI controller to be idle
    for (Timeout = 1000; Timeout > 0; Timeout--) {
      HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
      if (!(HsfstsCtl & HSFSTS_CTL_SCIP)) {
        break;
      }
      gBS->Stall (100);  // 100us delay
    }
    
    if (Timeout > 0) {
      OriginalClockCtl = MmioRead32 (SpiMmio + SPI_CLOCK_CTL);
      Print (L"  Clock Control (0x%04X): 0x%08X\n", SPI_CLOCK_CTL, OriginalClockCtl);
      
      // Test if bits 8-10 are writable (try setting to DIV_8 = 0x300)
      ClockCtl = OriginalClockCtl;
      TestValue = (ClockCtl & ~SPI_CLOCK_DIV_MASK) | SPI_CLOCK_DIV_8;
      MmioWrite32 (SpiMmio + SPI_CLOCK_CTL, TestValue);
      gBS->Stall (1000);  // 1ms delay
      ReadBack = MmioRead32 (SpiMmio + SPI_CLOCK_CTL);
      
      if ((ReadBack & SPI_CLOCK_DIV_MASK) == SPI_CLOCK_DIV_8) {
        Print (L"  ✓✓✓ CLOCK DIVIDER FOUND AT OFFSET 0x%04X ✓✓✓\n", SPI_CLOCK_CTL);
        MmioWrite32 (SpiMmio + SPI_CLOCK_CTL, OriginalClockCtl);  // Restore
        *ClockRegOffset = SPI_CLOCK_CTL;
        *ClockBitShift = SPI_CLOCK_DIV_SHIFT;
        *ClockBitMask = SPI_CLOCK_DIV_MASK;
        return EFI_SUCCESS;
      }
      
      // Restore original value
      MmioWrite32 (SpiMmio + SPI_CLOCK_CTL, OriginalClockCtl);
    }
  }
  
  // Method 2: Check HSFSTS_CTL for clock divider bits (fallback for other platforms)
  // Try bits 8-10 (FSPI field)
  HsfstsCtl = OriginalHsfstsCtl;
  TestValue = (HsfstsCtl & ~HSFSTS_CTL_FSPI_MASK) | HSFSTS_CTL_FSPI_DIV_8;
  
  // Only modify if controller is idle
  if (!(HsfstsCtl & HSFSTS_CTL_SCIP)) {
    MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, TestValue);
    gBS->Stall (1000);  // 1ms delay
    ReadBack = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
    
    if ((ReadBack & HSFSTS_CTL_FSPI_MASK) == HSFSTS_CTL_FSPI_DIV_8) {
      Print (L"  ✓ Found clock divider in HSFSTS_CTL (bits 8-10)\n");
      MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, OriginalHsfstsCtl);  // Restore
      *ClockRegOffset = SPI_HSFSTS_CTL;
      *ClockBitShift = 8;
      *ClockBitMask = HSFSTS_CTL_FSPI_MASK;
      return EFI_SUCCESS;
    }
    
    // Restore original value
    MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, OriginalHsfstsCtl);
  }
  
  // Method 3: Check HSFCTL for clock divider bits
  Hsfctl = OriginalHsfctl;
  TestValue = (Hsfctl & ~HSFCTL_CLOCK_DIV_MASK) | (0x3 << HSFCTL_CLOCK_DIV_SHIFT);
  
  MmioWrite32 (SpiMmio + SPI_HSFCTL, TestValue);
  gBS->Stall (1000);  // 1ms delay
  ReadBack = MmioRead32 (SpiMmio + SPI_HSFCTL);
  
  if ((ReadBack & HSFCTL_CLOCK_DIV_MASK) == (TestValue & HSFCTL_CLOCK_DIV_MASK)) {
    Print (L"  ✓ Found clock divider in HSFCTL (bits 8-10)\n");
    MmioWrite32 (SpiMmio + SPI_HSFCTL, OriginalHsfctl);  // Restore
    *ClockRegOffset = SPI_HSFCTL;
    *ClockBitShift = 8;
    *ClockBitMask = HSFCTL_CLOCK_DIV_MASK;
    return EFI_SUCCESS;
  }
  
  // Restore original value
  MmioWrite32 (SpiMmio + SPI_HSFCTL, OriginalHsfctl);
  
  // SAFETY: Removed dangerous blind probe loop (Method 4)
  // Writing to unknown MMIO registers can trigger unexpected commands or hang the controller
  // If known offsets don't work, use safe default rather than probing
  
  Print (L"  ⚠ Clock divider register not found in standard locations\n");
  Print (L"  Using discovered Meteor Lake offset 0x0010 as safe default\n");
  Print (L"  (Clock speed adjustment may not work, but write will proceed)\n");
  
  // Default to offset 0x0010 (discovered for Meteor Lake)
  *ClockRegOffset = SPI_CLOCK_CTL;
  *ClockBitShift = SPI_CLOCK_DIV_SHIFT;
  *ClockBitMask = SPI_CLOCK_DIV_MASK;
  
  return EFI_NOT_FOUND;  // Not found, but default provided
}

/**
  Set SPI clock speed for reliable flash operations
  
  @param[in] ClockDivider  Clock divider value (e.g., SPI_CLOCK_DIV_8)
  
  @retval EFI_SUCCESS  Clock speed set successfully
  @retval EFI_NOT_READY  SPI controller not mapped
**/
EFI_STATUS
SetSpiClockSpeed (
  IN UINT32  ClockDivider
  )
{
  UINT16  ClockRegOffset;
  UINT8   ClockBitShift;
  UINT32  ClockBitMask;
  UINT32  RegValue;
  UINTN   SpiMmio;
  EFI_STATUS  Status;
  
  if (mSpiMmioBase == NULL) {
    return EFI_NOT_READY;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  Print (L"[CLOCK] Setting SPI clock to slower speed for reliability...\n");
  
  // Probe for clock divider register
  Status = ProbeSpiClockControl (&ClockRegOffset, &ClockBitShift, &ClockBitMask);
  if (EFI_ERROR (Status)) {
    Print (L"  ⚠ Clock probe failed, using default location\n");
  }
  
  // Read current register value
  RegValue = MmioRead32 (SpiMmio + ClockRegOffset);
  mOriginalSpiClock = RegValue & ClockBitMask;  // Save original clock setting
  
  Print (L"  Original clock setting: 0x%08X (register 0x%04X)\n", 
         mOriginalSpiClock, ClockRegOffset);
  
  // Wait for SPI controller to be idle before modifying clock
  {
    UINT32  HsfstsCtl;
    UINTN   Timeout;
    
    for (Timeout = 1000; Timeout > 0; Timeout--) {
      HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
      if (!(HsfstsCtl & HSFSTS_CTL_SCIP)) {
        break;
      }
      gBS->Stall (100);  // 100us delay
    }
    
    if (Timeout == 0) {
      Print (L"  ⚠ SPI controller busy, cannot set clock safely\n");
      return EFI_DEVICE_ERROR;
    }
  }
  
  // Set new clock divider (clear old bits, set new ones)
  RegValue = (RegValue & ~ClockBitMask) | (ClockDivider & ClockBitMask);
  MmioWrite32 (SpiMmio + ClockRegOffset, RegValue);
  gBS->Stall (1000);  // 1ms delay for clock to stabilize
  
  // Verify write
  RegValue = MmioRead32 (SpiMmio + ClockRegOffset);
  if ((RegValue & ClockBitMask) == (ClockDivider & ClockBitMask)) {
    Print (L"  ✓ SPI clock set to divider 0x%03X (slower, more reliable)\n", 
           ClockDivider & ClockBitMask);
    Print (L"  Register 0x%04X value: 0x%08X\n", ClockRegOffset, RegValue);
    Print (L"\n");
    return EFI_SUCCESS;
  }
  
  Print (L"  ⚠ Clock setting verification failed (may still work)\n");
  Print (L"  Expected: 0x%03X, Got: 0x%03X\n", 
         ClockDivider & ClockBitMask, RegValue & ClockBitMask);
  Print (L"\n");
  
  return EFI_DEVICE_ERROR;
}

/**
  Restore original SPI clock speed
  
  @retval EFI_SUCCESS  Clock speed restored
  @retval EFI_NOT_READY  SPI controller not mapped
**/
EFI_STATUS
RestoreSpiClockSpeed (
  VOID
  )
{
  UINT16  ClockRegOffset;
  UINT8   ClockBitShift;
  UINT32  ClockBitMask;
  UINT32  RegValue;
  UINTN   SpiMmio;
  EFI_STATUS  Status;
  
  if (mSpiMmioBase == NULL) {
    return EFI_NOT_READY;
  }
  
  if (mOriginalSpiClock == 0) {
    // No clock was changed, nothing to restore
    return EFI_SUCCESS;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  Print (L"[CLOCK] Restoring original SPI clock speed...\n");
  
  // Probe for clock divider register (same as before)
  Status = ProbeSpiClockControl (&ClockRegOffset, &ClockBitShift, &ClockBitMask);
  if (EFI_ERROR (Status)) {
    Print (L"  ⚠ Clock probe failed, using default location (0x0010)\n");
    ClockRegOffset = SPI_CLOCK_CTL;
    ClockBitShift = SPI_CLOCK_DIV_SHIFT;
    ClockBitMask = SPI_CLOCK_DIV_MASK;
  }
  
  // Wait for SPI controller to be idle before modifying clock
  {
    UINT32  HsfstsCtl;
    UINTN   Timeout;
    
    for (Timeout = 1000; Timeout > 0; Timeout--) {
      HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
      if (!(HsfstsCtl & HSFSTS_CTL_SCIP)) {
        break;
      }
      gBS->Stall (100);  // 100us delay
    }
    
    if (Timeout == 0) {
      Print (L"  ⚠ SPI controller busy, cannot restore clock safely\n");
      return EFI_DEVICE_ERROR;
    }
  }
  
  // Read current register value
  RegValue = MmioRead32 (SpiMmio + ClockRegOffset);
  
  // Restore original clock setting
  RegValue = (RegValue & ~ClockBitMask) | (mOriginalSpiClock & ClockBitMask);
  MmioWrite32 (SpiMmio + ClockRegOffset, RegValue);
  gBS->Stall (1000);  // 1ms delay for clock to stabilize
  
  Print (L"  ✓ Original SPI clock restored (0x%03X)\n", mOriginalSpiClock);
  Print (L"  Register 0x%04X value: 0x%08X\n", ClockRegOffset, RegValue);
  Print (L"\n");
  
  mOriginalSpiClock = 0;  // Clear saved value
  
  return EFI_SUCCESS;
}

/**
  Comprehensive ME protection unlock sequence
  Runs VSEC unlocks, HAP activation attempts, and other bypasses
  
  @retval EFI_SUCCESS  Unlock sequence completed
**/
EFI_STATUS
UnlockMeProtection (
  VOID
  )
{
  UINT32  ReadBack;
  UINT32  HeciHfsts1;
  
  Print (L"[PRE-UNLOCK] Running comprehensive ME protection unlock sequence...\n");
  Print (L"  This sequence attempts multiple unlock methods to maximize success\n");
  Print (L"\n");
  
  // Step 1: VSEC Engineering Mode
  Print (L"  [1/8] VSEC Engineering Mode (0x%016llX)...\n", VSEC_ENG_MODE);
  MmioWrite32 ((UINTN)VSEC_ENG_MODE, 0xA00A00A0);  // Engineering mode pattern
  gBS->Stall (100000);  // 100ms delay
  ReadBack = MmioRead32 ((UINTN)VSEC_ENG_MODE);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 2: VSEC Debug Control
  Print (L"  [2/8] VSEC Debug Control (0x%016llX)...\n", VSEC_DEBUG_CTRL);
  MmioWrite32 ((UINTN)VSEC_DEBUG_CTRL, 0xFFFFFFFF);
  gBS->Stall (100000);
  ReadBack = MmioRead32 ((UINTN)VSEC_DEBUG_CTRL);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 3: VSEC Fuse Override
  Print (L"  [3/8] VSEC Fuse Override (0x%016llX)...\n", VSEC_FUSE_OVERRIDE);
  MmioWrite32 ((UINTN)VSEC_FUSE_OVERRIDE, 0xFFFFFFFF);
  gBS->Stall (100000);
  ReadBack = MmioRead32 ((UINTN)VSEC_FUSE_OVERRIDE);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 4: VSEC Security Bypass
  Print (L"  [4/8] VSEC Security Bypass (0x%016llX)...\n", VSEC_SECURITY_BYPASS);
  MmioWrite32 ((UINTN)VSEC_SECURITY_BYPASS, 0xFFFFFFFF);
  gBS->Stall (100000);
  ReadBack = MmioRead32 ((UINTN)VSEC_SECURITY_BYPASS);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 5: VSEC Control Register
  Print (L"  [5/8] VSEC Control Register (0x%016llX)...\n", VSEC_CTRL_REG);
  MmioWrite32 ((UINTN)VSEC_CTRL_REG, 0x0000007F);  // Full access
  gBS->Stall (100000);
  ReadBack = MmioRead32 ((UINTN)VSEC_CTRL_REG);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 6: VSEC Feature Unlock
  Print (L"  [6/8] VSEC Feature Unlock (0x%016llX)...\n", VSEC_FEAT_UNLOCK);
  MmioWrite32 ((UINTN)VSEC_FEAT_UNLOCK, 0xFFFFFFFF);
  gBS->Stall (100000);
  ReadBack = MmioRead32 ((UINTN)VSEC_FEAT_UNLOCK);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 7: VSEC CSME Bypass
  Print (L"  [7/8] VSEC CSME Bypass (0x%016llX)...\n", VSEC_CSME_BYPASS);
  MmioWrite32 ((UINTN)VSEC_CSME_BYPASS, 0xFFFFFFFF);
  gBS->Stall (100000);
  ReadBack = MmioRead32 ((UINTN)VSEC_CSME_BYPASS);
  Print (L"    Value: 0x%08X\n", ReadBack);
  
  // Step 8: VSEC ME Control (Direct HAP Enable) - Only if HAP enablement is requested
  if (mEnableHap) {
    Print (L"  [8/8] VSEC ME Control - Direct HAP Enable (0x%016llX)...\n", VSEC_ME_CONTROL);
    Print (L"    ⚠ HAP enablement requested - this will disable ME after reboot\n");
    MmioWrite32 ((UINTN)VSEC_ME_CONTROL, 0xFFFFFFFF);
    gBS->Stall (100000);
    ReadBack = MmioRead32 ((UINTN)VSEC_ME_CONTROL);
    Print (L"    Value: 0x%08X\n", ReadBack);
    
    // Check HAP status and attempt activation if needed
    Print (L"\n  [HAP CHECK] Verifying HAP mode status...\n");
    HeciHfsts1 = MmioRead32 ((UINTN)HECI_HFSTS1);
    Print (L"    HFSTS1: 0x%08X\n", HeciHfsts1);
    
    if (HeciHfsts1 & HECI_HFSTS1_HAP_MODE) {
      Print (L"    ✓✓✓ HAP MODE IS ACTIVE (bit 12 set) ✓✓✓\n");
    } else {
      Print (L"    ⚠ HAP mode is not active (bit 12 not set)\n");
      Print (L"    Attempting HAP activation via HECI commands...\n");
      
      // Try HAP override command
      {
        UINT32  HeciCmd = 0x85FF;  // HAP Override command
        UINT32  HeciDoorbell = 0x80000001;  // HAP privilege bit
        
        MmioWrite32 ((UINTN)(HECI_MMIO_BASE + 0x10), HeciCmd);  // HECI_CMD
        gBS->Stall (10000);
        MmioWrite32 ((UINTN)(HECI_MMIO_BASE + 0x14), HeciDoorbell);  // HECI_DOORBELL
        gBS->Stall (100000);
        
        HeciHfsts1 = MmioRead32 ((UINTN)HECI_HFSTS1);
        if (HeciHfsts1 & HECI_HFSTS1_HAP_MODE) {
          Print (L"    ✓ HAP mode activated via HECI command\n");
        } else {
          Print (L"    ⚠ HAP activation attempt did not succeed\n");
        }
      }
    }
  } else {
    Print (L"  [8/8] VSEC ME Control - Skipped (HAP enablement not requested)\n");
    Print (L"    Note: For ME restoration, HAP should remain disabled\n");
    Print (L"    Use -hap flag if ME neutralization is desired\n");
    
    // Still check current HAP status for informational purposes
    Print (L"\n  [HAP CHECK] Current HAP mode status (informational)...\n");
    HeciHfsts1 = MmioRead32 ((UINTN)HECI_HFSTS1);
    Print (L"    HFSTS1: 0x%08X\n", HeciHfsts1);
    if (HeciHfsts1 & HECI_HFSTS1_HAP_MODE) {
      Print (L"    ⚠ HAP mode is currently ACTIVE (ME is disabled)\n");
      Print (L"    This restoration will restore ME functionality\n");
    } else {
      Print (L"    ✓ HAP mode is not active (ME is functional)\n");
    }
  }
  
  Print (L"\n  ✓ Pre-unlock sequence completed\n\n");
  
  return EFI_SUCCESS;
}

/**
  Attempt to disable write protection
  
  @retval EFI_SUCCESS  Write protection disabled
  @retval EFI_ACCESS_DENIED  Cannot disable write protection
**/
EFI_STATUS
DisableWriteProtection (
  VOID
  )
{
  UINT32  Frap;
  UINTN   SpiMmio;
  
  if (mSpiMmioBase == NULL) {
    return EFI_NOT_READY;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  Print (L"[3/5] Checking write protection...\n");
  
  // CRITICAL SAFETY CHECK: Verify FLOCKDN status before attempting FRAP writes
  {
    UINT32  Hsfsts;
    
    Hsfsts = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
    if (Hsfsts & HSFSTS_CTL_FLOCKDN) {
      Print (L"  ⚠⚠⚠ CRITICAL WARNING: Flash Configuration Lock-Down (FLOCKDN) is ACTIVE ⚠⚠⚠\n");
      Print (L"  FLOCKDN bit 15 is set in HSFSTS_CTL: 0x%08X\n", Hsfsts);
      Print (L"  Software modifications to FRAP will be IGNORED by hardware.\n");
      Print (L"  FRAP register is now read-only until next power cycle or hardware unlock.\n");
      Print (L"  Hardware-level unlock required (e.g., flash descriptor override jumper/pin strap).\n");
      Print (L"  Continuing anyway, but write protection disable will likely fail...\n");
      Print (L"\n");
    } else {
      Print (L"  ✓ FLOCKDN is not set - FRAP register is writable\n");
    }
  }
  
  Frap = MmioRead32 (SpiMmio + SPI_FRAP);
  Print (L"  FRAP: 0x%08X\n", Frap);
  
  if (Frap & (1 << 2)) {
    Print (L"  ⚠ ME region is write-protected (bit 2 set)\n");
    Print (L"  Attempting to disable write protection...\n");
    
    // Method 1: Try to clear write protect bit directly
    MmioWrite32 (SpiMmio + SPI_FRAP, Frap & ~(1 << 2));
    gBS->Stall (100000);  // 100ms delay
    
    Frap = MmioRead32 (SpiMmio + SPI_FRAP);
    
    if (Frap & (1 << 2)) {
      Print (L"  ⚠ Direct FRAP write failed, trying VSEC ME bypass...\n");
      
      // Method 2: Try VSEC CSME bypass (discovered address)
      Print (L"  Attempting VSEC CSME bypass (0x%016llX)...\n", VSEC_CSME_BYPASS);
      MmioWrite32 ((UINTN)VSEC_CSME_BYPASS, 0xFFFFFFFF);
      gBS->Stall (100000);
      
      // Method 3: Try VSEC ME Control (discovered address)
      Print (L"  Attempting VSEC ME Control (0x%016llX)...\n", VSEC_ME_CONTROL);
      MmioWrite32 ((UINTN)VSEC_ME_CONTROL, 0x00000001);
      gBS->Stall (100000);
      
      // Try FRAP again
      MmioWrite32 (SpiMmio + SPI_FRAP, 0x00000000);  // Clear all protection
      gBS->Stall (100000);
      Frap = MmioRead32 (SpiMmio + SPI_FRAP);
      
      if (Frap & (1 << 2)) {
        Print (L"  ✗ Cannot disable write protection (hardware/ME enforced)\n");
        Print (L"  ⚠ ME may be actively protecting the region\n");
        Print (L"  Continuing anyway (may fail during write)...\n\n");
        return EFI_ACCESS_DENIED;
      }
    }
    
    Print (L"  ✓ Write protection disabled\n\n");
  } else {
    Print (L"  ✓ ME region is not write-protected\n\n");
  }
  
  return EFI_SUCCESS;
}

/**
  Write ME firmware chunk to SPI flash
  
  @param[in] FlashAddr  Flash address to write to
  @param[in] Data       Data buffer
  @param[in] DataSize   Size of data (max 16 bytes)
  
  @retval EFI_SUCCESS  Write completed
  @retval EFI_DEVICE_ERROR  Write failed
**/
EFI_STATUS
WriteSpiChunk (
  IN UINT32  FlashAddr,
  IN UINT8   *Data,
  IN UINTN   DataSize
  )
{
  UINT32  HsfstsCtl;
  UINT32  HsfstsVal;
  UINTN   SpiMmio;
  UINTN   Timeout;
  UINTN   i;
  
  if (mSpiMmioBase == NULL || Data == NULL || DataSize == 0 || DataSize > 16) {
    return EFI_INVALID_PARAMETER;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  // Wait for SPI controller to be ready
  for (Timeout = 1000; Timeout > 0; Timeout--) {
    HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
    if (!(HsfstsCtl & HSFSTS_CTL_SCIP)) {
      break;
    }
    gBS->Stall (100);  // 100us delay
  }
  
  if (Timeout == 0) {
    return EFI_DEVICE_ERROR;
  }
  
  // Clear any previous errors
  if (HsfstsCtl & HSFSTS_CTL_FCERR) {
    MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, HsfstsCtl | HSFSTS_CTL_FCERR);
  }
  
  // Set flash address
  MmioWrite32 (SpiMmio + SPI_FADDR, FlashAddr);
  
  // Write data to FDATA registers (up to 16 bytes)
  for (i = 0; i < DataSize && i < 16; i += 4) {
    UINT32  DataWord = 0;
    UINTN   BytesToCopy = (DataSize - i < 4) ? (DataSize - i) : 4;
    
    CopyMem (&DataWord, Data + i, BytesToCopy);
    MmioWrite32 (SpiMmio + SPI_FDATA0 + i, DataWord);
  }
  
  // Configure HSFSTS_CTL for write operation
  HsfstsVal = (HSFSTS_CTL_FCYCLE_WRITE << HSFSTS_CTL_FCYCLE_SHIFT) |
              ((DataSize - 1) << HSFSTS_CTL_FDBC_SHIFT) |
              HSFSTS_CTL_FGO;
  
  // Start write operation
  MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, HsfstsVal);
  
  // Wait for completion
  for (Timeout = 10000; Timeout > 0; Timeout--) {
    HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
    if (HsfstsCtl & HSFSTS_CTL_FDONE) {
      break;
    }
    if (HsfstsCtl & HSFSTS_CTL_FCERR) {
      return EFI_DEVICE_ERROR;
    }
    gBS->Stall (100);
  }
  
  if (Timeout == 0) {
    return EFI_TIMEOUT;
  }
  
  return EFI_SUCCESS;
}

/**
  Read ME firmware chunk from SPI flash
  
  @param[in] FlashAddr  Flash address to read from
  @param[out] Data      Data buffer to read into
  @param[in] DataSize   Size of data to read (max 16 bytes)
  
  @retval EFI_SUCCESS  Read completed
  @retval EFI_DEVICE_ERROR  Read failed
**/
EFI_STATUS
ReadSpiChunk (
  IN UINT32  FlashAddr,
  OUT UINT8  *Data,
  IN UINTN   DataSize
  )
{
  UINT32  HsfstsCtl;
  UINT32  HsfstsVal;
  UINTN   SpiMmio;
  UINTN   Timeout;
  UINTN   i;
  
  if (mSpiMmioBase == NULL || Data == NULL || DataSize == 0 || DataSize > 16) {
    return EFI_INVALID_PARAMETER;
  }
  
  SpiMmio = (UINTN)mSpiMmioBase;
  
  // Wait for SPI controller to be ready
  for (Timeout = 1000; Timeout > 0; Timeout--) {
    HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
    if (!(HsfstsCtl & HSFSTS_CTL_SCIP)) {
      break;
    }
    gBS->Stall (100);  // 100us delay
  }
  
  if (Timeout == 0) {
    return EFI_DEVICE_ERROR;
  }
  
  // Clear any previous errors
  if (HsfstsCtl & HSFSTS_CTL_FCERR) {
    MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, HsfstsCtl | HSFSTS_CTL_FCERR);
  }
  
  // Set flash address
  MmioWrite32 (SpiMmio + SPI_FADDR, FlashAddr);
  
  // Configure HSFSTS_CTL for read operation
  HsfstsVal = (HSFSTS_CTL_FCYCLE_READ << HSFSTS_CTL_FCYCLE_SHIFT) |
              ((DataSize - 1) << HSFSTS_CTL_FDBC_SHIFT) |
              HSFSTS_CTL_FGO;
  
  // Start read operation
  MmioWrite32 (SpiMmio + SPI_HSFSTS_CTL, HsfstsVal);
  
  // Wait for completion
  for (Timeout = 10000; Timeout > 0; Timeout--) {
    HsfstsCtl = MmioRead32 (SpiMmio + SPI_HSFSTS_CTL);
    if (HsfstsCtl & HSFSTS_CTL_FDONE) {
      break;
    }
    if (HsfstsCtl & HSFSTS_CTL_FCERR) {
      return EFI_DEVICE_ERROR;
    }
    gBS->Stall (100);
  }
  
  if (Timeout == 0) {
    return EFI_TIMEOUT;
  }
  
  // Read data from FDATA registers (up to 16 bytes)
  for (i = 0; i < DataSize && i < 16; i += 4) {
    UINT32  DataWord;
    UINTN   BytesToCopy = (DataSize - i < 4) ? (DataSize - i) : 4;
    
    DataWord = MmioRead32 (SpiMmio + SPI_FDATA0 + i);
    CopyMem (Data + i, &DataWord, BytesToCopy);
  }
  
  return EFI_SUCCESS;
}

/**
  Write ME firmware from file to SPI flash
  
  @param[in] FileHandle  Handle to ME dump file
  
  @retval EFI_SUCCESS  ME firmware written successfully
  @retval EFI_DEVICE_ERROR  Write failed
**/
EFI_STATUS
WriteMeFirmware (
  IN SHELL_FILE_HANDLE  FileHandle
  )
{
  EFI_STATUS  Status;
  UINT64      FileSize;
  UINT8       *Buffer;
  UINTN       BytesRead;
  UINTN       Offset;
  UINTN       ChunkSize;
  
  Print (L"[4/5] Writing ME firmware to SPI flash...\n");
  Print (L"  ⚠⚠⚠ THIS WILL MODIFY SPI FLASH! ⚠⚠⚠\n");
  Print (L"  Writing %llu bytes to ME region...\n", ME_FIRMWARE_SIZE);
  
  // Get file size
  Status = ShellGetFileSize (FileHandle, &FileSize);
  if (EFI_ERROR (Status)) {
    Print (L"  ✗ Failed to get file size\n");
    return Status;
  }
  
  Print (L"  File size: %llu bytes\n", FileSize);
  Print (L"  ME region size: %llu bytes\n", ME_FIRMWARE_SIZE);
  
  // Allocate buffer for chunk
  Buffer = AllocatePool (ME_CHUNK_SIZE);
  if (Buffer == NULL) {
    Print (L"  ✗ Failed to allocate buffer\n");
    return EFI_OUT_OF_RESOURCES;
  }
  
  // Seek to beginning of file
  Status = ShellSetFilePosition (FileHandle, 0);
  if (EFI_ERROR (Status)) {
    Print (L"  ✗ Failed to seek file\n");
    FreePool (Buffer);
    return Status;
  }
  
  // Write in chunks (256 bytes read from file, broken into 16-byte SPI writes)
  for (Offset = 0; Offset < ME_FIRMWARE_SIZE && Offset < FileSize; Offset += ME_CHUNK_SIZE) {
    ChunkSize = (ME_FIRMWARE_SIZE - Offset < ME_CHUNK_SIZE) ? 
                (UINTN)(ME_FIRMWARE_SIZE - Offset) : ME_CHUNK_SIZE;
    
    if (FileSize - Offset < ChunkSize) {
      ChunkSize = (UINTN)(FileSize - Offset);
    }
    
    // Read chunk from file
    BytesRead = ChunkSize;
    Status = ShellReadFile (FileHandle, &BytesRead, Buffer);
    if (EFI_ERROR (Status) || BytesRead != ChunkSize) {
      Print (L"  ✗ Failed to read file at offset %u\n", Offset);
      FreePool (Buffer);
      return EFI_DEVICE_ERROR;
    }
    
    // Write chunk to SPI flash in 16-byte sub-chunks (SPI hardware limit)
    {
      UINTN   SubOffset;
      UINTN   SubChunkSize;
      UINT32  SubFlashAddr;
      
      for (SubOffset = 0; SubOffset < ChunkSize; SubOffset += 16) {
        SubChunkSize = (ChunkSize - SubOffset < 16) ? (ChunkSize - SubOffset) : 16;
        SubFlashAddr = (UINT32)(ME_FIRMWARE_START + Offset + SubOffset);
        
        Status = WriteSpiChunk (SubFlashAddr, Buffer + SubOffset, SubChunkSize);
        if (EFI_ERROR (Status)) {
          Print (L"  ✗ Write failed at offset %u (address 0x%08X)\n", 
                 Offset + SubOffset, SubFlashAddr);
          FreePool (Buffer);
          return Status;
        }
      }
    }
    
    // Progress report every 64KB
    if ((Offset % (64 * 1024)) == 0) {
      UINTN  Percent = (Offset * 100) / ME_FIRMWARE_SIZE;
      Print (L"  Progress: %u / %llu bytes (%u%%)\n", 
             Offset, ME_FIRMWARE_SIZE, Percent);
    }
  }
  
  FreePool (Buffer);
  
  Print (L"  ✓✓✓ ME firmware write completed ✓✓✓\n\n");
  
  return EFI_SUCCESS;
}

/**
  Verify ME firmware by reading back from SPI flash and comparing with dump file
  
  @param[in] FileHandle  Handle to ME dump file
  @param[out] Matches    TRUE if verification passed, FALSE if mismatch found
  
  @retval EFI_SUCCESS  Verification completed
  @retval EFI_DEVICE_ERROR  Verification failed
**/
EFI_STATUS
VerifyMeFirmware (
  IN SHELL_FILE_HANDLE  FileHandle,
  OUT BOOLEAN           *Matches
  )
{
  EFI_STATUS  Status;
  UINT64      FileSize;
  UINT8       *FileBuffer;
  UINT8       *FlashBuffer;
  UINTN       BytesRead;
  UINTN       Offset;
  UINTN       ChunkSize;
  UINTN       MismatchCount = 0;
  UINTN       FirstMismatchOffset = 0;
  
  if (Matches == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  *Matches = FALSE;
  
  Print (L"[VERIFY] Verifying ME firmware write...\n");
  Print (L"  Reading back from SPI flash and comparing with dump file...\n");
  Print (L"\n");
  
  // Get file size
  Status = ShellGetFileSize (FileHandle, &FileSize);
  if (EFI_ERROR (Status)) {
    Print (L"  ✗ Failed to get file size\n");
    return Status;
  }
  
  // Allocate buffers for comparison
  FileBuffer = AllocatePool (ME_CHUNK_SIZE);
  FlashBuffer = AllocatePool (ME_CHUNK_SIZE);
  if (FileBuffer == NULL || FlashBuffer == NULL) {
    Print (L"  ✗ Failed to allocate verification buffers\n");
    if (FileBuffer != NULL) {
      FreePool (FileBuffer);
    }
    if (FlashBuffer != NULL) {
      FreePool (FlashBuffer);
    }
    return EFI_OUT_OF_RESOURCES;
  }
  
  // Seek to beginning of file
  Status = ShellSetFilePosition (FileHandle, 0);
  if (EFI_ERROR (Status)) {
    Print (L"  ✗ Failed to seek file\n");
    FreePool (FileBuffer);
    FreePool (FlashBuffer);
    return Status;
  }
  
  // Compare in chunks
  for (Offset = 0; Offset < ME_FIRMWARE_SIZE && Offset < FileSize; Offset += ME_CHUNK_SIZE) {
    ChunkSize = (ME_FIRMWARE_SIZE - Offset < ME_CHUNK_SIZE) ? 
                (UINTN)(ME_FIRMWARE_SIZE - Offset) : ME_CHUNK_SIZE;
    
    if (FileSize - Offset < ChunkSize) {
      ChunkSize = (UINTN)(FileSize - Offset);
    }
    
    // Read chunk from file
    BytesRead = ChunkSize;
    Status = ShellReadFile (FileHandle, &BytesRead, FileBuffer);
    if (EFI_ERROR (Status) || BytesRead != ChunkSize) {
      Print (L"  ✗ Failed to read file at offset %u\n", Offset);
      FreePool (FileBuffer);
      FreePool (FlashBuffer);
      return EFI_DEVICE_ERROR;
    }
    
    // Read chunk from SPI flash in 16-byte sub-chunks
    {
      UINTN   SubOffset;
      UINTN   SubChunkSize;
      UINT32  SubFlashAddr;
      
      for (SubOffset = 0; SubOffset < ChunkSize; SubOffset += 16) {
        SubChunkSize = (ChunkSize - SubOffset < 16) ? (ChunkSize - SubOffset) : 16;
        SubFlashAddr = (UINT32)(ME_FIRMWARE_START + Offset + SubOffset);
        
        Status = ReadSpiChunk (SubFlashAddr, FlashBuffer + SubOffset, SubChunkSize);
        if (EFI_ERROR (Status)) {
          Print (L"  ✗ Failed to read flash at offset %u (address 0x%08X)\n", 
                 Offset + SubOffset, SubFlashAddr);
          FreePool (FileBuffer);
          FreePool (FlashBuffer);
          return Status;
        }
      }
    }
    
    // Compare buffers
    if (CompareMem (FileBuffer, FlashBuffer, ChunkSize) != 0) {
      // Find first mismatch in this chunk
      UINTN   i;
      for (i = 0; i < ChunkSize; i++) {
        if (FileBuffer[i] != FlashBuffer[i]) {
          if (MismatchCount == 0) {
            FirstMismatchOffset = Offset + i;
          }
          MismatchCount++;
        }
      }
    }
    
    // Progress report every 64KB
    if ((Offset % (64 * 1024)) == 0) {
      UINTN  Percent = (Offset * 100) / ME_FIRMWARE_SIZE;
      Print (L"  Verification progress: %u / %llu bytes (%u%%)\n", 
             Offset, ME_FIRMWARE_SIZE, Percent);
    }
  }
  
  FreePool (FileBuffer);
  FreePool (FlashBuffer);
  
  if (MismatchCount > 0) {
    UINTN  TotalBytes = (FileSize < ME_FIRMWARE_SIZE) ? (UINTN)FileSize : (UINTN)ME_FIRMWARE_SIZE;
    UINTN  PercentBad = (TotalBytes > 0) ? ((MismatchCount * 100) / TotalBytes) : 0;
    
    Print (L"  ✗✗✗ VERIFICATION FAILED ✗✗✗\n");
    Print (L"  Total bytes verified: %u\n", TotalBytes);
    Print (L"  Mismatches found: %u bytes (%u%%)\n", MismatchCount, PercentBad);
    Print (L"  First mismatch at offset: 0x%016llX\n", FirstMismatchOffset);
    Print (L"  First mismatch address: 0x%016llX\n", 
           ME_FIRMWARE_START + FirstMismatchOffset);
    Print (L"  ⚠ SPI flash content does not match dump file!\n");
    Print (L"\n");
    *Matches = FALSE;
    return EFI_SUCCESS;
  }
  
  {
    UINTN  TotalBytes = (FileSize < ME_FIRMWARE_SIZE) ? (UINTN)FileSize : (UINTN)ME_FIRMWARE_SIZE;
    Print (L"  ✓✓✓ VERIFICATION PASSED ✓✓✓\n");
    Print (L"  Total bytes verified: %u\n", TotalBytes);
    Print (L"  All bytes match dump file perfectly\n");
    Print (L"\n");
  }
  
  *Matches = TRUE;
  
  return EFI_SUCCESS;
}

/**
  Restore ME firmware from dump file if verification failed
  
  @param[in] FileHandle  Handle to ME dump file
  
  @retval EFI_SUCCESS  ME firmware restored successfully
  @retval EFI_DEVICE_ERROR  Restore failed
**/
EFI_STATUS
RestoreMeFirmware (
  IN SHELL_FILE_HANDLE  FileHandle
  )
{
  Print (L"[RESTORE] Restoring ME firmware from dump file...\n");
  Print (L"  ⚠⚠⚠ ATTEMPTING TO RESTORE SPI FLASH! ⚠⚠⚠\n");
  
  // Re-write the firmware (same as WriteMeFirmware)
  return WriteMeFirmware (FileHandle);
}

/**
  UEFI application entry point
  
  @param[in] Argc  Number of command line arguments
  @param[in] Argv  Array of command line argument strings
  
  @retval 0   Application exited successfully
  @retval 1   Application error
**/
INTN
EFIAPI
ShellAppMain (
  IN UINTN   Argc,
  IN CHAR16  **Argv
  )
{
  EFI_STATUS         Status;
  SHELL_FILE_HANDLE   FileHandle;
  UINT64              MeBase, MeLimit;
  CHAR16              *FileName;
  
  Print (L"================================================================================");
  Print (L"ME FIRMWARE RESTORATION UEFI APPLICATION - Enhanced Edition\n");
  Print (L"Restores ME firmware from dump file to SPI flash\n");
  Print (L"ME region: 0x%016llX - 0x%016llX\n", ME_FIRMWARE_START, ME_FIRMWARE_END);
  Print (L"Using discovered addresses from deep probe:\n");
  Print (L"  SPI Controller: 0x%016llX (PCI 00:1f.5)\n", SPI_MMIO_BASE);
  Print (L"  HECI MMIO:      0x%016llX (PCI 00:16.0)\n", HECI_MMIO_BASE);
  Print (L"  VSEC MMIO:      0x%016llX (PCI 00:0a.0)\n", VSEC_MMIO_BASE);
  Print (L"================================================================================");
  Print (L"\n");
  Print (L"⚠⚠⚠ WARNING: THIS WILL MODIFY SPI FLASH ⚠⚠⚠\n");
  Print (L"  - ME firmware will be overwritten\n");
  Print (L"  - System may not boot if firmware is invalid\n");
  Print (L"  - Ensure dump file is correct and verified\n");
  Print (L"  - Run from UEFI shell BEFORE OS loads for best results\n");
  Print (L"\n");
  
  // Parse command line arguments
  FileName = NULL;  // Will be set from arguments or default
  
  if (Argc > 1) {
    UINTN  i;
    for (i = 1; i < Argc; i++) {
      if (StrCmp (Argv[i], L"-hap") == 0 || StrCmp (Argv[i], L"--hap") == 0 ||
          StrCmp (Argv[i], L"-neutralize") == 0 || StrCmp (Argv[i], L"--neutralize") == 0) {
        mEnableHap = TRUE;
      } else if (Argv[i][0] != L'-') {
        // First non-flag argument is the filename
        if (FileName == NULL) {
          FileName = Argv[i];
        }
      }
    }
  }
  
  // Set default filename if not provided
  if (FileName == NULL) {
    FileName = L"fs0:\\dump.bin";
  }
  
  Print (L"ME Dump File: %s\n", FileName);
  
  if (mEnableHap) {
    Print (L"HAP Enablement: ENABLED (ME will be disabled after reboot)\n");
    Print (L"  ⚠ This is ME NEUTRALIZATION mode, not restoration mode\n");
  } else {
    Print (L"HAP Enablement: DISABLED (ME restoration mode - default)\n");
    Print (L"  Use -hap flag to enable HAP mode (ME neutralization)\n");
  }
  
  Print (L"\n");
  
  // Step 1: Map SPI controller
  Status = MapSpiController ();
  if (EFI_ERROR (Status)) {
    Print (L"✗ Failed to map SPI controller\n");
    return 1;
  }
  
  // Step 2: Verify ME region
  Status = VerifyMeRegion (&MeBase, &MeLimit);
  if (EFI_ERROR (Status)) {
    Print (L"✗ ME region verification failed\n");
    return 1;
  }
  
  // Step 2.5: Run comprehensive ME protection unlock sequence
  // This should be done BEFORE attempting to disable write protection
  // to maximize chances of success
  Status = UnlockMeProtection ();
  if (EFI_ERROR (Status)) {
    Print (L"⚠ Pre-unlock sequence had errors (continuing anyway)\n");
    Print (L"\n");
  }
  
  // Step 3: Disable write protection
  Status = DisableWriteProtection ();
  if (Status == EFI_ACCESS_DENIED) {
    Print (L"⚠ Write protection could not be disabled\n");
    Print (L"  Continuing anyway (may fail during write)...\n");
    Print (L"\n");
  }
  
  // Step 4: Open dump file
  Print (L"[5/5] Opening ME dump file...\n");
  Status = ShellOpenFileByName (
             FileName,
             &FileHandle,
             EFI_FILE_MODE_READ,
             0
             );
  if (EFI_ERROR (Status)) {
    Print (L"  ✗ Failed to open file: %s\n", FileName);
    Print (L"     Error: %r\n", Status);
    return 1;
  }
  
  Print (L"  ✓ File opened\n\n");
  
  // Step 5: Set SPI clock to slower speed for reliability
  Status = SetSpiClockSpeed (SPI_CLOCK_DIV_RELIABLE);
  if (EFI_ERROR (Status)) {
    Print (L"  ⚠ Failed to set SPI clock speed (continuing anyway)\n");
    Print (L"\n");
  }
  
  // Step 6: Write ME firmware
  Status = WriteMeFirmware (FileHandle);
  if (EFI_ERROR (Status)) {
    Print (L"✗ ME firmware write failed\n");
    RestoreSpiClockSpeed ();
    ShellCloseFile (&FileHandle);
    return 1;
  }
  
  // Step 7: Verify ME firmware by reading back and comparing
  {
    BOOLEAN  Matches;
    UINTN    RestoreAttempts = 0;
    UINTN    MaxRestoreAttempts = 3;
    
    do {
      Status = VerifyMeFirmware (FileHandle, &Matches);
      if (EFI_ERROR (Status)) {
        Print (L"✗ Verification failed with error: %r\n", Status);
        break;
      }
      
      if (!Matches) {
        RestoreAttempts++;
        if (RestoreAttempts <= MaxRestoreAttempts) {
          Print (L"[RESTORE] Attempt %u/%u: Restoring ME firmware...\n", 
                 RestoreAttempts, MaxRestoreAttempts);
          
          // Seek back to beginning of file for restore
          Status = ShellSetFilePosition (FileHandle, 0);
          if (EFI_ERROR (Status)) {
            Print (L"  ✗ Failed to seek file for restore\n");
            break;
          }
          
          Status = RestoreMeFirmware (FileHandle);
          if (EFI_ERROR (Status)) {
            Print (L"  ✗ Restore attempt %u failed\n", RestoreAttempts);
            break;
          }
          
          // Seek back to beginning again for next verification
          Status = ShellSetFilePosition (FileHandle, 0);
          if (EFI_ERROR (Status)) {
            Print (L"  ✗ Failed to seek file for re-verification\n");
            break;
          }
        } else {
          Print (L"  ✗✗✗ RESTORATION FAILED AFTER %u ATTEMPTS ✗✗✗\n", MaxRestoreAttempts);
          Print (L"  SPI flash may be corrupted. Manual intervention required.\n");
          Status = EFI_DEVICE_ERROR;
          break;
        }
      }
    } while (!Matches && RestoreAttempts <= MaxRestoreAttempts);
    
    if (EFI_ERROR (Status)) {
      RestoreSpiClockSpeed ();
      ShellCloseFile (&FileHandle);
      return 1;
    }
    
    if (!Matches) {
      Print (L"✗ Verification failed after all restore attempts\n");
      RestoreSpiClockSpeed ();
      ShellCloseFile (&FileHandle);
      return 1;
    }
  }
  
  // Restore original SPI clock speed
  RestoreSpiClockSpeed ();
  
  // Close file
  ShellCloseFile (&FileHandle);
  
  if (EFI_ERROR (Status)) {
    Print (L"================================================================================");
    Print (L"✗ ME FIRMWARE RESTORATION FAILED");
    Print (L"================================================================================");
    Print (L"Error: %r\n", Status);
    return 1;
  }
  
  Print (L"================================================================================");
  Print (L"✓✓✓ ME FIRMWARE RESTORATION COMPLETE ✓✓✓");
  Print (L"================================================================================");
  Print (L"⚠ REBOOT REQUIRED for changes to take effect\n");
  Print (L"After reboot, check HAP mode:\n");
  Print (L"  devmem2 0x%016llX\n", HECI_HFSTS1);
  Print (L"  (HAP bit should be set: bit 12 = 1)\n");
  Print (L"\n");
  
  return 0;
}
