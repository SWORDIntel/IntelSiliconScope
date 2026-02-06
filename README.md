# IntelSiliconScope (iSS)

Linux-native firmware toolkit for Intel platforms. Unofficial ports of Intel's proprietary Windows tools.

## What This Is

Collection of tools to read, write, and analyze Intel firmware on Linux without needing Windows.

## Tools Included

- **gbe-nvm-toolkit/** - Intel GbE NVM management (flashrom, MMIO, ethtool)
- **intel_platform_flash_tool/** - Intel's official flash tool + analysis scripts
- **flashrom/** - Universal SPI flash read/write
- **edk2_shell_pkg/** - UEFI shell with custom commands
- **emba/** - Firmware security scanner
- **devmem2/** - Direct /dev/mem access utility

## Quick Start

```bash
# Install deps
sudo apt install build-essential python3 flashrom ethtool wine64

# Clone and build
git clone https://github.com/SWORDIntel/IntelSiliconScope.git
cd IntelSiliconScope
make all

# Use the tools
cd gbe-nvm-toolkit
sudo ./gbe_nvm_update.sh detect
sudo ./gbe_nvm_update.sh read backup.bin
```

## Usage Examples

### GbE NVM Recovery
```bash
# Generate fresh NVM with your MAC
./gbe_nvm_update.sh generate nvm.bin DE:11:54:50:99:69

# Flash it
sudo ./gbe_nvm_update.sh write nvm.bin

# Reload driver or reboot
sudo ./gbe_nvm_update.sh reload
```

### SPI Flash Dump
```bash
cd flashrom
sudo ./builddir/flashrom -p internal -r full_flash.bin

# Extract regions
dd if=full_flash.bin of=gbe.bin bs=1 skip=$((0x124000)) count=8192
dd if=full_flash.bin of=me.bin bs=1 skip=$((0x126000)) count=$((0xEC8000-0x126000))
```

### ME Analysis
```bash
cd intel_platform_flash_tool
./scripts/extract_me_version.sh me.bin
./scripts/analyze_me_dump_structure.sh me.bin
```

## Environment Variables

```bash
export GBE_PCI_BDF="0000:00:1f.6"  # Your GbE PCI address
export DSMIL_DEBUG=1                # Verbose output
```

## Warning

⚠️ **This modifies firmware. Can brick hardware. Backup first. Test on spare systems.**

Some ops need kernel module signing disabled. Know what you're doing.

## License

MIT. See LICENSE.

Individual components have their own licenses:
- Intel tools - Intel's license
- flashrom - GPL v2
- EMBA - GPL v3
- EDK2 - BSD + Patent

## Support

Unofficial ports of Intel proprietary tools. You're on your own buddy.

---

IntelSiliconScope (iSS) - scope out your silicon
