# IntelSiliconScope (iSS)

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/dsmil/intel-silicon-scope)
[![Platform](https://img.shields.io/badge/Platform-Linux-yellow.svg)](https://www.linux.org/)

Comprehensive firmware analysis, manipulation, and security toolkit for Intel platforms. Native Linux replacement for proprietary Windows firmware tools.

**iSS** - Intel Silicon Scope: Precision firmware analysis and manipulation toolkit.

## 🚀 Features

### 🔧 Core Tools
- **GbE NVM Toolkit** - Native Linux Intel GbE NVM management
- **Intel Platform Flash Tool** - Official Intel firmware flashing utility
- **flashrom** - Universal SPI flash reading/writing
- **EDK2 Shell** - UEFI shell environment with DSMIL extensions
- **EMBA** - Firmware security analysis scanner

### 🎯 Capabilities
- **SPI Flash Operations** - Read/write/verify firmware regions
- **ME/CSME Analysis** - Intel Management Engine firmware inspection
- **GbE NVM Management** - Ethernet controller firmware manipulation
- **UEFI Shell Integration** - Pre-boot firmware operations
- **Security Assessment** - Automated firmware vulnerability scanning

## 📁 Project Structure

```
IntelSiliconScope/
├── README.md                    # This file
├── LICENSE                      # MIT License
├── Makefile                     # Build system
├── gbe-nvm-toolkit/             # Intel GbE NVM management
│   ├── gbe_nvm_update.sh        # Main NVM toolkit
│   ├── gbe_nvm_mmio.py          # Direct MMIO access
│   ├── gbe_nvm_ethtool.sh       # Driver-level access
│   └── README.md                # GbE toolkit docs
├── intel_platform_flash_tool/  # Intel's official tool
│   ├── platformflashtoollite/   # Extracted tool binaries
│   ├── scripts/                 # ME analysis scripts
│   └── docs/                    # Tool documentation
├── flashrom/                    # Universal SPI flash utility
│   ├── builddir/                # Build output
│   └── README_DSMIL.md          # DSMIL integration
├── edk2_shell_pkg/              # UEFI shell with DSMIL extensions
│   ├── Application/MeRestoreApp/ # ME restore app
│   └── DynamicCommand/DsmilUnlockCommand/ # DSMIL unlock
├── emba/                        # Firmware security scanner
│   ├── emba                     # Main scanner script
│   └── config/                  # Scanner configuration
├── devmem2/                     # Direct memory access utility
│   ├── devmem2                  # Binary utility
│   └── Makefile                 # Build instructions
├── docs/                        # Comprehensive documentation
│   ├── INSTALLATION.md          # Setup guide
│   ├── USAGE.md                 # Usage examples
│   ├── SECURITY.md              # Security considerations
│   └── API.md                   # API reference
├── scripts/                     # Helper scripts
│   ├── setup.sh                 # Environment setup
│   ├── build_all.sh             # Build all components
│   └── test_tools.sh            # Test suite
├── examples/                    # Usage examples
│   ├── gbe_restore/             # GbE restoration examples
│   ├── me_analysis/             # ME analysis examples
│   └── flash_operations/        # Flash operation examples
├── tests/                       # Test suite
│   ├── unit/                    # Unit tests
│   └── integration/             # Integration tests
└── licenses/                    # Component licenses
    ├── intel/                   # Intel tool licenses
    ├── flashrom/                # flashrom license
    └── emba/                    # EMBA license
```

## 🛠️ Quick Start

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y build-essential python3 python3-pip \
    flashrom ethtool wine64 git

# Optional: for full functionality
sudo apt install -y qemu-kvm libguestfs-tools
```

### Installation

```bash
# Clone the repository
git clone https://github.com/dsmil/intel-silicon-scope.git
cd intel-silicon-scope

# Build all components
make all

# Install system-wide (optional)
sudo make install
```

### Basic Usage

#### GbE NVM Management
```bash
cd gbe-nvm-toolkit

# Detect Intel GbE controller
sudo ./gbe_nvm_update.sh detect

# Read current NVM from SPI flash
sudo ./gbe_nvm_update.sh read backup.bin

# Show NVM information
./gbe_nvm_update.sh info backup.bin

# Restore NVM (full procedure)
sudo ./gbe_nvm_update.sh restore
```

#### SPI Flash Operations
```bash
cd flashrom

# Build flashrom
meson setup builddir
meson compile -C builddir

# Read full SPI flash
sudo ./builddir/flashrom -p internal -r full_flash.bin

# Extract GbE region
dd if=full_flash.bin of=gbe.bin bs=1 skip=$((0x124000)) count=8192
```

#### ME Firmware Analysis
```bash
cd intel_platform_flash_tool

# Extract ME version from dump
./scripts/extract_me_version.sh me_region.bin

# Analyze ME structure
./scripts/analyze_me_dump_structure.sh me_region.bin
```

#### Firmware Security Scanning
```bash
cd emba

# Scan firmware image
sudo ./emba -f firmware.bin -o scan_results/

# Scan live system
sudo ./emba -s -o system_scan/
```

## 🎯 Use Cases

### 1. GbE NVM Recovery
Restore corrupted Intel GbE NVM after firmware wipe or corruption.

```bash
# Generate default NVM with custom MAC
./gbe_nvm_update.sh generate default.bin DE:11:54:50:99:69

# Flash to SPI
sudo ./gbe_nvm_update.sh write default.bin

# Reload driver
sudo ./gbe_nvm_update.sh reload
```

### 2. ME Firmware Analysis
Analyze Intel Management Engine firmware for security assessment.

```bash
# Dump ME region
sudo flashrom -p internal -r flash.bin
dd if=flash.bin of=me.bin bs=1 skip=$((0x126000)) count=$((0xEC8000-0x126000))

# Analyze with ME tools
./intel_platform_flash_tool/scripts/analyze_me_dump_structure.sh me.bin
```

### 3. UEFI Shell Operations
Perform firmware operations before OS boot.

```bash
# Build EDK2 shell with DSMIL extensions
cd edk2_shell_pkg
make

# Deploy to EFI partition
sudo cp Build/ShellBase/DEBUG_GCC5/X64/Shell.efi /boot/efi/EFI/dsmil/
```

### 4. Security Assessment
Comprehensive firmware security analysis.

```bash
# Full firmware scan
sudo emba/emba -f /path/to/firmware.bin -o security_report/

# GbE NVM validation
./gbe-nvm-toolkit/gbe_nvm_update.sh verify nvm.bin
```

## 🔧 Advanced Configuration

### Environment Variables
```bash
# Set PCI BDF for GbE controller
export GBE_PCI_BDF="0000:00:1f.6"

# Set flashrom programmer
export FLASHROM_PROGRAMMER="internal"

# Enable debug output
export DSMIL_DEBUG=1
```

### Configuration Files
- `~/.config/dsmil/firmware-toolkit.conf` - User configuration
- `/etc/dsmil/firmware-toolkit.conf` - System configuration

## 🛡️ Security Considerations

⚠️ **WARNING**: This toolkit modifies system firmware. Improper use can permanently brick hardware.

- Always backup firmware before modifications
- Test on non-production systems first
- Use with proper authorization and legal compliance
- Some operations require kernel module signing disabled

See [SECURITY.md](docs/SECURITY.md) for detailed security guidelines.

## 📚 Documentation

- [Installation Guide](docs/INSTALLATION.md) - Detailed setup instructions
- [Usage Examples](docs/USAGE.md) - Comprehensive usage examples
- [API Reference](docs/API.md) - Programming interfaces
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup
```bash
# Clone with submodules
git clone --recursive https://github.com/dsmil/firmware-toolkit.git

# Install development dependencies
sudo apt install -y clang-format cppcheck valgrind

# Run tests
make test

# Code formatting
make format
```

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

Individual components may have separate licenses:

- **Intel Platform Flash Tool** - Intel Development Tools Limited License Agreement
- **flashrom** - GPL v2
- **EMBA** - GPL v3
- **EDK2** - BSD + Patent Grant

See [licenses/](licenses/) directory for component-specific licenses.

## 🙏 Acknowledgments

- **Intel Corporation** - Platform Flash Tool and documentation
- **flashrom project** - Universal SPI flash utility
- **EMBA project** - Firmware security analysis framework
- **EDK2/TianoCore** - UEFI development kit
- **coreboot community** - Firmware documentation and tools

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/dsmil/firmware-toolkit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dsmil/firmware-toolkit/discussions)
- **Security**: security@dsmil.local

## 🗺️ Roadmap

- [ ] GUI interface for common operations
- [ ] Automated firmware vulnerability assessment
- [ ] Support for additional Intel platforms
- [ ] Cloud-based firmware analysis service
- [ ] Integration with DSMIL unlock system

---

**IntelSiliconScope (iSS)** - Precision firmware analysis and manipulation toolkit.

*For authorized use only. Use responsibly and in compliance with applicable laws and regulations.*
