# Intel Platform Flash Tool Lite - Analysis Summary

## Tool Overview

**Name**: Intel Platform Flash Tool Lite  
**Version**: 5.8.9.0  
**Source**: https://github.com/projectceladon/tools  
**Purpose**: Flashing firmware and OS images on Intel-based devices  
**Platform Support**: Windows, Linux (Ubuntu/Fedora), macOS

## Tool Components

### Executables

1. **platformflashtoollite** (5.1M)
   - Main GUI application
   - Requires Qt5 libraries
   - Primary interface for firmware flashing

2. **platformflashtoollitecli** (wrapper script)
   - CLI wrapper for GUI tool
   - Calls main binary with `--cli` flag

3. **flsTool** (1.2M)
   - FLS file manipulation utility
   - Actions: pack, extract, inject, dump metadata
   - Can extract image parts from FLS files
   - **Useful for**: Analyzing firmware images

4. **downloadTool** (1.2M)
   - Firmware download utility
   - Part of Intel flashing infrastructure

5. **dfu-util** (131K)
   - USB Device Firmware Upgrade utility
   - For DFU protocol devices

6. **fastboot** (1.5M)
   - Android fastboot protocol tool
   - For Android device flashing

7. **adb** (2.3M)
   - Android Debug Bridge
   - For Android device communication

8. **dnxFwDownloader** (44K)
   - DNX firmware downloader
   - For Intel SoC firmware

9. **xfstkFlashTool** (20K)
   - XFSTK flash tool
   - For Intel SoC flashing

## Key Findings

### For ME Firmware Dumping

**Intel Platform Flash Tool Lite is primarily for FLASHING, not READING**:
- Designed to write firmware to devices
- Does not appear to have direct SPI flash read capabilities
- GUI/CLI tools focus on flashing operations

**flsTool can analyze FLS files**:
- Can extract image parts from FLS files
- Can dump metadata from FLS files
- Useful if you already have an FLS firmware file
- **Not useful for**: Reading directly from SPI flash

### Recommended Approach for ME Dump

**Use `flashrom` instead**:
- `flashrom` is specifically designed for reading/writing SPI flash
- Supports Intel SPI controllers
- Can read entire flash or specific regions
- More suitable for ME firmware dumping

**Installation**:
```bash
sudo apt install flashrom
```

**Usage**:
```bash
# Read entire flash
sudo flashrom -p internal -r full_flash.bin

# Extract ME region (0x02000000-0x03FFF000)
dd if=full_flash.bin of=me_region.bin bs=1 skip=$((0x02000000)) count=$((0x01FFF000))
```

## Tool Capabilities

### What Intel Platform Flash Tool Lite CAN Do:
- ✅ Flash firmware images to Intel devices
- ✅ Extract/analyze FLS firmware files (via flsTool)
- ✅ Support multiple flashing protocols (DFU, fastboot, etc.)
- ✅ GUI and CLI interfaces

### What Intel Platform Flash Tool Lite CANNOT Do:
- ❌ Read SPI flash directly from hardware
- ❌ Dump ME firmware from running system
- ❌ Analyze raw SPI flash dumps

## Integration with DSMIL System

### Current Status:
1. ✅ Tool downloaded and extracted to `tools/intel_platform_flash_tool/`
2. ✅ Kernel module (Stage 5) can read SPI controller registers (FRAP, FREG1)
3. ✅ ME region boundaries discovered: `0x02000000-0x03FFF000`
4. ⏳ `flashrom` installation recommended for full ME dump

### Next Steps:
1. Install `flashrom` for SPI flash reading
2. Use `flashrom` to dump full flash or ME region
3. Analyze ME firmware dump for HAP bit location
4. Use Intel Platform Flash Tool Lite (or flashrom) for flashing if modifications needed

## Documentation

- **User Guide**: `platformflashtoollite_extracted/opt/intel/platformflashtoollite/doc/Platform_Flash_Tool_Lite_User_Guide.pdf`
- **License**: Intel Development Tools Limited License Agreement
- **Source**: https://github.com/projectceladon/tools

## Conclusion

Intel Platform Flash Tool Lite is useful for **flashing** firmware but not for **reading/dumping** ME firmware. For ME firmware analysis, use:
1. **flashrom** - For reading SPI flash
2. **flsTool** - For analyzing existing FLS firmware files
3. **Kernel module (Stage 5)** - For reading SPI controller registers and region boundaries
