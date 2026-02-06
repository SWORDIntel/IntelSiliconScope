# flashrom for DSMIL System

This directory contains the flashrom source code cloned from [GitHub](https://github.com/flashrom/flashrom).

## Repository Information

- **Source**: https://github.com/flashrom/flashrom
- **Version**: v1.6.0-83-gbccc0f8e (latest main branch)
- **License**: GPL-2.0
- **Purpose**: Utility for detecting, reading, writing, verifying and erasing flash chips

## Building flashrom

flashrom is built with **meson**. Quick build:

```bash
cd tools/FLASHROM
meson setup builddir
meson compile -C builddir
meson test -C builddir
sudo meson install -C builddir
```

For detailed build instructions, see the [official documentation](https://www.flashrom.org/).

## Using flashrom for IFWI Extraction

### Extract IFWI from SPI Flash

```bash
# Read full flash
sudo flashrom -p internal -r full_flash.bin

# Extract BIOS/IFWI region (FREG1: 0x02000000-0x03FFFFFF)
dd if=full_flash.bin of=ifwi_blob.bin bs=1 skip=$((0x02000000)) count=$((0x02000000))
```

### Flash Region Layout

From Intel Platform Flash Tool analysis:
- **FREG0**: 0x00000000-0x00003FFF (16KB) - Flash Descriptor (read-only)
- **FREG1**: 0x02000000-0x03FFFFFF (32MB) - BIOS/UEFI/IFWI (read-write)
- **FREG2**: 0x00126000-0x00EC7FFF (~14.5MB) - ME Firmware (read-only)
- **FREG3**: 0x00124000-0x00125FFF (8KB) - GbE (read-write)
- **FREG8**: 0x00004000-0x00123FFF (~1.1MB) - EC/BMC (locked)
- **FREG9**: 0x00EC8000-0x01FFFFFF (~19MB) - Device Expansion (read-only)

### Integration with IFWI Extraction Tools

The IFWI extraction scripts in `tools/CCTK-MILSPEC/Firmware Patching/` can use flashrom:

```bash
# Run complete extraction (includes flashrom IFWI extraction if available)
sudo tools/CCTK-MILSPEC/Firmware\ Patching/extract_all.sh
```

## Safety Warnings

⚠️ **CRITICAL**:
- **Reading SPI flash is generally safe** (read-only operations)
- **Writing/modifying flash can BRICK the system permanently**
- Always backup full flash before any modifications
- Test on non-production systems first
- ME region is read-only - cannot be written via flashrom

## References

- **Official Website**: https://www.flashrom.org/
- **GitHub Repository**: https://github.com/flashrom/flashrom
- **Documentation**: See `doc/` directory in this repository
- **IFWI Extraction Tools**: `tools/CCTK-MILSPEC/Firmware Patching/`

## Related Tools

- **Intel Platform Flash Tool**: `tools/intel_platform_flash_tool/`
- **IFWI Metadata Extractor**: `tools/CCTK-MILSPEC/Firmware Patching/ifwi_metadata_extractor.py`
- **IFWI Deep Analyzer**: `tools/CCTK-MILSPEC/Firmware Patching/ifwi_deep_analyzer.py`
