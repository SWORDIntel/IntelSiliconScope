# ME Firmware Restoration via Kernel Module

## Overview

This document describes the kernel module-based method for restoring ME firmware directly to SPI flash, bypassing ME write protection.

## Critical Safety Features

The kernel module includes **comprehensive validation** to ensure we write to the correct location:

### 1. FREG Register Scanning
- Reads ALL FREG registers (FREG0, FREG1, FREG2, FREG3)
- Automatically detects which register contains the ME region
- Verifies the found region matches expected addresses: `0x00126000 - 0x00EC7FFF`

### 2. Address Validation
- Verifies target address matches expected ME region start: `0x00126000`
- Verifies write size doesn't exceed ME region size: `~14.5MB`
- Aborts immediately if addresses don't match

### 3. Dump File Validation
- Validates dump file size matches ME region or known 16MB dump
- Verifies file can be read successfully
- Adjusts write size if dump is smaller than ME region

### 4. Pre-Write Verification
- Final validation before any write operation
- Confirms all parameters are correct
- Aborts if any validation fails

## ME Region Addresses

**Expected ME Region (from flashrom)**:
- Start: `0x00126000`
- End: `0x00EC7FFF`
- Size: `14,295,040 bytes` (~13.6 MB)

**Hardcoded in module**:
```c
#define ME_FIRMWARE_START  0x00126000ULL
#define ME_FIRMWARE_END    0x00EC7FFFULL
#define ME_FIRMWARE_SIZE   (ME_FIRMWARE_END - ME_FIRMWARE_START + 1)
```

## Usage

### Method 1: Using the Restoration Script

```bash
sudo tools/intel_platform_flash_tool/restore_me_via_kernel_module.sh
```

The script will:
1. Check for ME dump file
2. Verify module exists
3. Load module with Stage 6 (ME firmware write)
4. Display results

### Method 2: Manual Module Loading

```bash
sudo insmod scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.ko \
    run_stage=6 \
    me_dump_path=/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin
```

### Method 3: Using Procfs Interface

```bash
# Load module first
sudo insmod scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.ko \
    me_dump_path=/path/to/me_dump_16mb.bin

# Then trigger Stage 6 via procfs
echo 6 | sudo tee /proc/dsmil_unlock/run_stage
```

## How It Works

1. **SPI Controller Access**: Module accesses Intel SPI controller (PCI device 8086:7E23)

2. **FREG Register Scanning**: Reads all FREG registers to find ME region

3. **Validation**: Verifies addresses match expected ME region

4. **Write Protection Check**: Checks FRAP register for write protection

5. **Dump File Reading**: Reads ME dump file into kernel memory

6. **SPI Hardware Sequencing**: Uses Intel SPI Hardware Sequencing Flash (HSF) registers:
   - `HSFSTS_CTL`: Control/status register
   - `FADDR`: Flash address register
   - `FDATA0-3`: Flash data registers
   - Writes in 256-byte chunks

7. **Progress Reporting**: Reports progress every 64KB

## Safety Mechanisms

### Automatic Abort Conditions

The module will **ABORT** if:
- ME region not found in any FREG register
- Found region doesn't match expected addresses
- Dump file size doesn't match expected size
- Target address doesn't match expected ME region start
- Write size exceeds ME region size
- Cannot disable write protection

### Error Messages

All errors are clearly logged with:
- `✗✗✗ CRITICAL ERROR` prefix
- Detailed explanation of what went wrong
- Expected vs. actual values
- Clear abort message

## Verification After Write

After successful write, verify ME firmware:

```bash
# Check HAP mode status
sudo devmem2 0x50192DD040

# Check ME version
cat /sys/class/mei/mei*/version

# Read ME region from flash (if possible)
sudo flashrom -p internal -r /tmp/verify_me.bin -l flash_layout.txt
```

## Expected Results

### Successful Write
- Module logs: `✓✓✓ ME REGION CONFIRMED`
- Module logs: `✓✓✓ ALL VALIDATIONS PASSED`
- Module logs: `✓ ME firmware write completed`
- Module logs: `✓✓✓ Stage 6 completed - ME firmware written to SPI flash!`

### Failed Write
- Module logs: `✗✗✗ CRITICAL ERROR` with specific reason
- Module aborts before any write operation
- System remains safe (no partial writes)

## Troubleshooting

### "ME region not found in any FREG"
- SPI controller may not be accessible
- ME region may be at different addresses
- Check dmesg for SPI controller errors

### "Dump size mismatch"
- Verify dump file is correct
- Check file size: `ls -lh me_dump_16mb.bin`
- Expected: 16MB (16777216 bytes) or ME region size

### "Cannot disable write protection"
- ME may be actively protecting the region
- May need HAP mode enabled first
- May need HMRFPO command via HECI

### "Write timeout/error"
- SPI controller may be busy
- Flash chip may be locked at hardware level
- Check dmesg for detailed error messages

## Warnings

⚠️ **CRITICAL WARNINGS**:
- This writes directly to SPI flash
- Incorrect addresses can **BRICK** the system
- Always verify addresses before writing
- Ensure ME dump is from the same platform
- Have a backup of current flash before proceeding

## Related Files

- Module: `scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.c`
- Restoration script: `tools/intel_platform_flash_tool/restore_me_via_kernel_module.sh`
- ME dump: `docs/sorted_by_topic/hardware_probing/lat5150_me_dumps/me_dump_16mb.bin`

## References

- Flashrom documentation: ME region at `0x00126000-0x00EC7FFF` (FREG2)
- Intel SPI Controller: Hardware Sequencing Flash registers
- ME Firmware: Version `0:18.0.18.2571` (from system)
