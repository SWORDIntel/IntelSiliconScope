# ME Firmware Dump Guide

## Overview

This guide explains how to dump and analyze the ME (Management Engine) firmware from SPI flash for HAP bit location and modification.

## Discovered ME Region

From kernel module probing:
- **ME Region Base**: `0x02000000` (32MB offset in SPI flash)
- **ME Region Limit**: `0x03FFF000` (ends at ~64MB)
- **FRAP (Flash Region Access)**: `0x00004ACF`
- **FREG1 (ME Region Register)**: `0x3FFF2000`
- **ME Version**: `0:18.0.18.2571`
- **ME Status**: `0x94000245`

## Tools Available

### 1. Intel Platform Flash Tool Lite

**Location**: `/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/intel_platform_flash_tool/`

**Version**: 5.8.9.0

**Download**: https://github.com/projectceladon/tools

**Components**:
- `platformflashtoollite` - GUI tool
- `platformflashtoollitecli` - CLI tool (wrapper)
- `flsTool` - FLS file manipulation tool (extract, pack, dump metadata)

**Usage**:
```bash
# Set library path
export LD_LIBRARY_PATH=/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/intel_platform_flash_tool/platformflashtoollite_extracted/opt/intel/platformflashtoollite/lib:$LD_LIBRARY_PATH

# Run GUI tool
/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/intel_platform_flash_tool/platformflashtoollite_extracted/opt/intel/platformflashtoollite/bin/platformflashtoollite

# Run CLI tool
/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/tools/intel_platform_flash_tool/platformflashtoollite_extracted/usr/bin/platformflashtoollitecli --help
```

**Note**: Intel Platform Flash Tool Lite is primarily for flashing firmware, not reading. For reading/dumping, use `flashrom` instead.

### 2. flashrom (Recommended for Dumping)

**Installation**:
```bash
sudo apt install flashrom
```

**Usage for ME Dump**:
```bash
# Read entire flash (includes ME region)
sudo flashrom -p internal -r full_flash_dump.bin

# Read only ME region (if flashrom supports region selection)
# ME region: 0x02000000-0x03FFF000
sudo flashrom -p internal -r me_dump.bin -l flashlayout.txt
```

**Flash Layout File** (`flashlayout.txt`):
```
0x00000000:0x01FFFFFF BIOS
0x02000000:0x03FFFFFF ME
0x04000000:0x04FFFFFF GbE
0x05000000:0x05FFFFFF Platform Data
```

### 3. Kernel Module ME Dump (Stage 5)

**Location**: `/media/user/593d876a-4036-4255-bd45-33baba503068/DSMILSystem/scripts/unlock/modules-6.12.63+deb13-amd64/hap_forced_microcode/max_potency_module/`

**Usage**:
```bash
# Load module with stage 5 (ME dump)
sudo insmod hap_device255_me_tpm_coordinated.ko run_stage=5

# Or use procfs
sudo insmod hap_device255_me_tpm_coordinated.ko
echo 5 | sudo tee /proc/dsmil_unlock/run_stage
```

**Output**: `/tmp/me_firmware_dump.bin` (contains region info, not full dump)

**Note**: Kernel module currently only reads SPI controller registers (FRAP, FREG1) for region boundaries. Full SPI flash read requires hardware sequencing implementation or external tools.

## ME Firmware Analysis

### HAP Bit Location (ME Version 0:18.0.18.2571)

The HAP bit location varies by ME firmware version. For version `0:18.0.18.2571`, typical locations:

1. **ME Firmware Header**:
   - Offset: `0x02000000 + 0x10-0x20` (first 32 bytes of ME region)
   - Contains: ME signature, version, flags

2. **ME Firmware Configuration Region**:
   - Offset: `0x02000000 + 0x1000-0x2000` (4KB-8KB into ME region)
   - Contains: ME configuration, HAP mode settings

3. **ME Firmware Status Region**:
   - Offset: `0x02000000 + 0x2000-0x3000` (8KB-12KB into ME region)
   - Contains: ME status, HAP bit state

### Analysis Tools

1. **Hex Editor**: `hexdump`, `xxd`, `ghex`
   ```bash
   hexdump -C me_dump.bin | grep -A 5 -B 5 "pattern"
   ```

2. **ME Analyzer Tools**:
   - `me_analyzer` (if available)
   - `Intel ME System Tools` (proprietary)
   - Custom Python scripts for ME firmware parsing

3. **Strings Search**:
   ```bash
   strings me_dump.bin | grep -i "hap\|disable\|enable"
   ```

## Next Steps

1. **Dump Full ME Firmware**:
   ```bash
   sudo flashrom -p internal -r me_firmware_full.bin
   # Extract ME region (0x02000000-0x03FFF000)
   dd if=me_firmware_full.bin of=me_region.bin bs=1 skip=$((0x02000000)) count=$((0x01FFF000))
   ```

2. **Analyze ME Firmware**:
   - Search for HAP-related strings/patterns
   - Locate ME firmware header
   - Identify HAP bit location in configuration region

3. **Modify HAP Bit** (EXTREMELY DANGEROUS):
   - **WARNING**: Modifying ME firmware can brick the system!
   - Use specialized tools (Intel Flash Image Tool, MEConfig)
   - Or modify via SPI flash controller (requires hardware sequencing)

4. **Verify HAP Activation**:
   - Check HFSTS1 register bit 12 (0x50192DD040)
   - Use kernel module: `echo 25 | sudo tee /proc/dsmil_unlock/run_stage`

## References

### Tools
- **Intel Platform Flash Tool Lite**: https://github.com/projectceladon/tools
- **flashrom**: https://www.flashrom.org/ - SPI flash reading/writing tool

### Community Resources
- **coreboot Documentation**: https://doc.coreboot.org/ - ME firmware and HAP bit information
- **me_cleaner Project**: https://github.com/corna/me_cleaner - ME firmware modification tools and documentation
- **flashrom Wiki**: https://www.flashrom.org/Flashrom - SPI flash documentation

### Local Tools
- Use `../scripts/python/find_hap_bit.py` for HAP bit location analysis
- Use `../scripts/python/analyze_me_firmware.py` for ME firmware structure analysis

### Note
Intel's official ME firmware documentation is proprietary and not publicly available. Community resources and the tools in this directory provide practical alternatives for ME firmware analysis.

## Safety Warnings

⚠️ **CRITICAL**: 
- Reading SPI flash is generally safe (read-only)
- **Writing/modifying ME firmware can BRICK the system permanently**
- Always backup full flash before any modifications
- Test on non-production systems first
- HAP bit modification requires deep understanding of ME firmware structure
