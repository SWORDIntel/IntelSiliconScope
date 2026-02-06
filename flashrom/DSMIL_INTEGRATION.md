# flashrom Integration with DSMIL Unlock System

## Overview

This document describes how flashrom integrates with the DSMIL unlock system, particularly for IFWI extraction and ME firmware operations.

## SPI Controller Information

From `scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.c`:

- **SPI Controller**: Intel Meteor Lake SPI Controller
- **Vendor ID**: 0x8086
- **Device ID**: 0x7E23
- **MMIO Base**: 0x7c120000
- **MMIO Size**: 0x1000 (4K)

## Flash Region Layout

From Intel Platform Flash Tool analysis and kernel module:

- **FREG0**: 0x00000000-0x00003FFF (16KB) - Flash Descriptor (read-only)
- **FREG1**: 0x02000000-0x03FFFFFF (32MB) - BIOS/UEFI/IFWI (read-write)
- **FREG2**: 0x00126000-0x00EC7FFF (~14.5MB) - ME Firmware (read-only)
- **FREG3**: 0x00124000-0x00125FFF (8KB) - GbE (read-write)
- **FREG8**: 0x00004000-0x00123FFF (~1.1MB) - EC/BMC (locked)
- **FREG9**: 0x00EC8000-0x01FFFFFF (~19MB) - Device Expansion (read-only)

## Integration Points

### 1. Kernel Module SPI Access

The kernel module `hap_device255_me_tpm_coordinated.c` has:
- SPI controller detection and MMIO mapping
- Flash region register reading (FRAP, FREG0-3)
- ME firmware dump capability (stage 5)
- ME firmware write capability (stage 6) - **DANGEROUS**

### 2. Rust SPI Scanner

`scripts/unlock/spi/src/main.rs` provides:
- Read-only SPI controller scanning
- Register value extraction
- Safety checks

### 3. flashrom Integration

flashrom can be used to:
- Read full SPI flash (safer than kernel module direct access)
- Extract IFWI from BIOS region (FREG1)
- Extract ME firmware from ME region (FREG2)
- Verify flash contents

## Usage with DSMIL System

### Extract IFWI from SPI Flash

```bash
# Read full flash
sudo flashrom -p internal -r full_flash.bin

# Extract IFWI (BIOS region: FREG1)
dd if=full_flash.bin of=ifwi_blob.bin bs=1 skip=$((0x02000000)) count=$((0x02000000))

# Extract ME firmware (FREG2)
dd if=full_flash.bin of=me_firmware.bin bs=1 skip=$((0x00126000)) count=$((0x00DB5FFF))
```

### Integration with IFWI Extraction Tools

The IFWI extraction scripts in `tools/CCTK-MILSPEC/Firmware Patching/` can use flashrom:

```bash
# Run complete extraction (includes flashrom IFWI extraction)
sudo tools/CCTK-MILSPEC/Firmware\ Patching/extract_all.sh
```

### Coordination with Kernel Module

The kernel module can:
1. Read SPI controller registers (FRAP, FREG values)
2. Verify flashrom can access the same regions
3. Coordinate ME firmware operations

## Safety Considerations

⚠️ **CRITICAL WARNINGS**:

1. **Reading is generally safe** - flashrom read operations are read-only
2. **Writing can BRICK** - Never write to SPI flash without proper backup
3. **ME region is read-only** - Cannot be written via flashrom (hardware protection)
4. **BIOS region can be written** - But requires careful coordination

## Potential Modifications Needed

### 1. SPI Controller Support

Check if flashrom fully supports Intel Meteor Lake SPI controller (8086:7E23):
- Verify in `programmers/ichspi.c` or similar
- May need to add device ID if not present

### 2. Flash Layout File

Create flash layout file for flashrom:
```
0x00000000:0x00003FFF FREG0
0x02000000:0x03FFFFFF FREG1
0x00126000:0x00EC7FFF FREG2
0x00124000:0x00125FFF FREG3
```

### 3. Integration Scripts

Create scripts that:
- Use flashrom for safe reading
- Coordinate with kernel module for register access
- Extract IFWI parts using existing tools

## Next Steps

1. **Verify flashrom support** for 8086:7E23 SPI controller
2. **Test flashrom read** operations on the system
3. **Create integration scripts** that coordinate flashrom with kernel module
4. **Document flash layout** for flashrom usage
5. **Add safety checks** before any write operations

## References

- Kernel Module: `scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/hap_device255_me_tpm_coordinated.c`
- SPI Scanner: `scripts/unlock/spi/src/main.rs`
- IFWI Tools: `tools/CCTK-MILSPEC/Firmware Patching/`
- Intel Platform Flash Tool: `tools/intel_platform_flash_tool/`
