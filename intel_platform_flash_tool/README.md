# Intel Platform Flash Tool Directory

This directory contains tools, scripts, and documentation for Intel Platform Flash operations, ME (Management Engine) firmware analysis, and SPI flash manipulation.

## Directory Structure

```
intel_platform_flash_tool/
├── README.md                          # This file
├── docs/                              # Documentation files
│   ├── ACCESS_DEGRADATION_ANALYSIS.md
│   ├── ACCESS_LOSS_DIAGNOSIS.md
│   ├── ANALYSIS_SUMMARY.md
│   ├── create_uefi_me_restore_app.md
│   ├── FLASH_REGIONS_EXPLAINED.md
│   ├── FLASHROM_ANALYSIS.md
│   ├── ME_FIRMWARE_DUMP_GUIDE.md
│   ├── ME_RESTORATION_VIA_KERNEL_MODULE.md
│   └── TOOL_ANALYSIS_COMPLETE.md
├── scripts/                           # Shell scripts
│   ├── analyze_me_dump_structure.sh
│   ├── diagnose_access_loss.sh
│   ├── extract_me_version.sh
│   ├── probe_spi_clock_control.sh
│   ├── read_me_region.sh
│   ├── restore_full_flash_from_me_dump.sh
│   ├── restore_full_flash.sh
│   ├── restore_me_firmware.sh
│   ├── restore_me_fit_method.sh
│   ├── restore_me_hmrfpo.sh
│   ├── restore_me_via_kernel_module.sh
│   ├── restore_me_with_intel_tools.sh
│   ├── verify_me_dump_for_restore.sh
│   └── python/                        # Python analysis scripts
│       ├── analyze_me_firmware.py
│       └── find_hap_bit.py
├── dumps/                             # Binary dump files
│   ├── flashrom_dump.bin
│   └── me_region_extracted_from_flash.bin
└── platformflashtoollite_extracted/  # Intel Platform Flash Tool Lite (extracted)
    ├── opt/intel/platformflashtoollite/
    └── usr/bin/
```

## Quick Reference

### Documentation (`docs/`)

- **ME_FIRMWARE_DUMP_GUIDE.md** - Complete guide for dumping and analyzing ME firmware
- **TOOL_ANALYSIS_COMPLETE.md** - Summary of Intel Platform Flash Tool and flashrom analysis
- **ANALYSIS_SUMMARY.md** - Overview of Intel Platform Flash Tool Lite capabilities
- **FLASHROM_ANALYSIS.md** - flashrom findings and flash region mapping
- **FLASH_REGIONS_EXPLAINED.md** - Detailed explanation of SPI flash regions
- **ACCESS_LOSS_DIAGNOSIS.md** - Troubleshooting guide for access issues
- **ACCESS_DEGRADATION_ANALYSIS.md** - Analysis of access degradation scenarios
- **ME_RESTORATION_VIA_KERNEL_MODULE.md** - Guide for ME restoration using kernel modules
- **create_uefi_me_restore_app.md** - Instructions for creating UEFI ME restore applications

### Scripts (`scripts/`)

#### Analysis Scripts
- `analyze_me_dump_structure.sh` - Analyzes structure of ME firmware dumps
- `extract_me_version.sh` - Extracts ME version information from dumps
- `diagnose_access_loss.sh` - Diagnoses SPI flash access issues
- `probe_spi_clock_control.sh` - Probes SPI clock control settings
- `read_me_region.sh` - Reads ME region from SPI flash

#### Restoration Scripts
- `restore_me_firmware.sh` - Main ME firmware restoration script
- `restore_full_flash.sh` - Restores entire SPI flash
- `restore_full_flash_from_me_dump.sh` - Restores flash using ME dump
- `restore_me_fit_method.sh` - ME restoration using FIT method
- `restore_me_hmrfpo.sh` - ME restoration using HMRFPO method
- `restore_me_via_kernel_module.sh` - ME restoration via kernel module
- `restore_me_with_intel_tools.sh` - ME restoration using Intel tools
- `verify_me_dump_for_restore.sh` - Verifies ME dump before restoration

#### Python Scripts (`scripts/python/`)
- `analyze_me_firmware.py` - Python script for ME firmware analysis
- `find_hap_bit.py` - Locates HAP (High Assurance Platform) bit in ME firmware

### Dumps (`dumps/`)

Binary files containing SPI flash dumps:
- `flashrom_dump.bin` - Full flash dump from flashrom
- `me_region_extracted_from_flash.bin` - Extracted ME region from flash dump

### Intel Platform Flash Tool Lite

Located in `platformflashtoollite_extracted/`:
- **Version**: 5.8.9.0
- **Source**: https://github.com/projectceladon/tools
- **Purpose**: Flashing firmware to Intel-based devices
- **Note**: Primarily for flashing, not reading. Use `flashrom` for reading/dumping.

## Usage Examples

### Reading ME Region
```bash
# Using flashrom
sudo flashrom -p internal -r full_flash.bin

# Extract ME region
dd if=full_flash.bin of=me_region.bin bs=1 skip=$((0x02000000)) count=$((0x01FFF000))
```

### Analyzing ME Firmware
```bash
# Analyze dump structure
./scripts/analyze_me_dump_structure.sh dumps/me_region_extracted_from_flash.bin

# Extract ME version
./scripts/extract_me_version.sh dumps/me_region_extracted_from_flash.bin

# Find HAP bit
python3 scripts/python/find_hap_bit.py dumps/me_region_extracted_from_flash.bin
```

### Restoring ME Firmware
```bash
# Verify dump before restore
./scripts/verify_me_dump_for_restore.sh dumps/me_region_extracted_from_flash.bin

# Restore ME firmware (choose appropriate method)
./scripts/restore_me_firmware.sh dumps/me_region_extracted_from_flash.bin
```

## Important Notes

⚠️ **CRITICAL WARNINGS**:
- **Reading SPI flash is generally safe** (read-only operations)
- **Writing/modifying ME firmware can BRICK the system permanently**
- Always backup full flash before any modifications
- Test on non-production systems first
- HAP bit modification requires deep understanding of ME firmware structure

## Flash Region Information

From analysis, the flash regions are:
- **FREG0**: 0x00000000-0x00003FFF (16KB) - Flash Descriptor (read-only)
- **FREG1**: 0x02000000-0x03FFFFFF (32MB) - BIOS/UEFI (read-write)
- **FREG2**: 0x00126000-0x00EC7FFF (~14.5MB) - ME Firmware (read-only)
- **FREG3**: 0x00124000-0x00125FFF (8KB) - GbE (read-write)
- **FREG8**: 0x00004000-0x00123FFF (~1.1MB) - EC/BMC (locked)
- **FREG9**: 0x00EC8000-0x01FFFFFF (~19MB) - Device Expansion (read-only)

## References

### Tools and Software
- **Intel Platform Flash Tool**: https://github.com/projectceladon/tools
- **flashrom**: https://www.flashrom.org/ - SPI flash reading/writing tool
- **me_analyzer**: Community tool for ME firmware analysis (if available)

### Community Resources
- **coreboot Documentation**: https://doc.coreboot.org/ - ME firmware and HAP bit information
- **me_cleaner Project**: https://github.com/corna/me_cleaner - ME firmware modification tools and documentation
- **flashrom Wiki**: https://www.flashrom.org/Flashrom - SPI flash documentation
- **Intel ME Wiki** (community maintained): Various community wikis and forums discussing ME firmware

### Local Documentation
- See `docs/ME_FIRMWARE_DUMP_GUIDE.md` for detailed ME analysis procedures
- See `docs/TOOL_ANALYSIS_COMPLETE.md` for tool capabilities and limitations
- See `docs/FLASHROM_ANALYSIS.md` for flash region mapping
- Use `scripts/python/find_hap_bit.py` for HAP bit location analysis
- Use `scripts/python/analyze_me_firmware.py` for ME firmware structure analysis

### Note on Proprietary Documentation
Intel's official ME firmware documentation is proprietary and not publicly available. The tools and scripts in this directory, along with community resources, provide practical alternatives for ME firmware analysis and manipulation.

## See Also

- `docs/ME_FIRMWARE_DUMP_GUIDE.md` - Complete ME dumping guide
- `docs/TOOL_ANALYSIS_COMPLETE.md` - Tool analysis summary
- `docs/FLASHROM_ANALYSIS.md` - flashrom findings
