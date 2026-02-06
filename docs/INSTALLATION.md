# Installation Guide

## System Requirements

### Supported Platforms
- **Linux** (Ubuntu 20.04+, Debian 11+, Fedora 35+, Arch Linux)
- **Kernel** 5.10+ (recommended 6.0+)
- **Architecture**: x86_64 (Intel platforms only)

### Hardware Requirements
- Intel platform with Management Engine (ME/CSME)
- Intel GbE Ethernet controller (I219-V/LM, I218-V/LM, I217-V/LM)
- SPI flash access (internal programmer)

## Prerequisites

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y \
    build-essential \
    python3 python3-pip python3-venv \
    meson ninja-build \
    git wget curl \
    flashrom ethtool \
    wine64 winbind \
    qemu-kvm libguestfs-tools \
    pciutils kmod \
    linux-headers-generic
```

### Fedora/RHEL
```bash
sudo dnf install -y \
    gcc gcc-c++ make \
    python3 python3-pip \
    meson ninja \
    git wget curl \
    flashrom ethtool \
    wine \
    qemu-kvm libguestfs-tools \
    pciutils kmod \
    kernel-devel
```

### Arch Linux
```bash
sudo pacman -S --needed \
    base-devel \
    python python-pip \
    meson ninja \
    git wget curl \
    flashrom ethtool \
    wine \
    qemu \
    pciutils kmod \
    linux-headers
```

## Installation Methods

### Method 1: Git Clone (Recommended)

```bash
# Clone the repository
git clone https://github.com/dsmil/firmware-toolkit.git
cd firmware-toolkit

# Check dependencies
make check-deps

# Build all components
make all

# Test installation
make test

# Install system-wide (optional)
sudo make install
```

### Method 2: Release Archive

```bash
# Download latest release
wget https://github.com/dsmil/firmware-toolkit/releases/latest/download/dsmil-firmware-toolkit.tar.gz
tar -xzf dsmil-firmware-toolkit.tar.gz
cd dsmil-firmware-toolkit

# Build and install
make all
sudo make install
```

### Method 3: Package Manager (Future)

```bash
# Ubuntu/Debian (planned)
sudo apt install dsmil-firmware-toolkit

# Fedora (planned)
sudo dnf install dsmil-firmware-toolkit

# Arch (AUR)
yay -S dsmil-firmware-toolkit
```

## Component-Specific Setup

### GbE NVM Toolkit

The GbE NVM toolkit requires no compilation but needs proper permissions:

```bash
# Make scripts executable
chmod +x gbe-nvm-toolkit/*.sh gbe-nvm-toolkit/*.py

# Test basic functionality
sudo ./gbe-nvm-toolkit/gbe_nvm_update.sh detect
```

### flashrom

Build from source for latest features:

```bash
cd flashrom
meson setup builddir
meson compile -C builddir

# Test
sudo ./builddir/flashrom --help
```

### Intel Platform Flash Tool

The Intel tool requires Wine for Windows executables:

```bash
# Configure Wine
winecfg

# Test Intel tool
cd intel_platform_flash_tool
wine platformflashtoollite_extracted/opt/intel/platformflashtoollite/bin/platformflashtoollite.exe --help
```

### EMBA Security Scanner

```bash
cd emba
sudo ./installer.sh

# Test
./emba -h
```

### EDK2 Shell Package

```bash
cd edk2_shell_pkg
source edksetup.sh
build -a X64 -p ShellPkg/ShellPkg.dsc
```

## Configuration

### Environment Variables

```bash
# Add to ~/.bashrc or ~/.zshrc
export DSMIL_FIRMWARE_TOOLKIT="/opt/dsmil-firmware-toolkit"
export PATH="$DSMIL_FIRMWARE_TOOLKIT/bin:$PATH"

# GbE controller PCI address (if not default)
export GBE_PCI_BDF="0000:00:1f.6"

# Flashrom programmer
export FLASHROM_PROGRAMMER="internal"

# Debug output
export DSMIL_DEBUG=1
```

### System Configuration

#### Kernel Module Loading

```bash
# Load required modules
sudo modprobe e1000e
sudo modprobe spi_intel
sudo modprobe intel_spi

# Make modules load on boot
echo "e1000e" | sudo tee -a /etc/modules-load.d/dsmil.conf
echo "spi_intel" | sudo tee -a /etc/modules-load.d/dsmil.conf
```

#### udev Rules

Create `/etc/udev/rules.d/99-dsmil-firmware.rules`:

```udev
# DSMIL Firmware Toolkit device permissions
KERNEL=="mem", MODE="0660", GROUP="dsmil"
SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x15fc", MODE="0660", GROUP="dsmil"
```

```bash
# Create dsmil group
sudo groupadd dsmil
sudo usermod -a -G dsmil $USER

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

#### Wine Configuration

```bash
# Configure Wine for 32-bit support
winecfg

# Install required Windows components
winetricks vcrun2019
```

## Verification

### Basic Functionality Test

```bash
# Test GbE detection
sudo gbe-nvm-update detect

# Test flashrom
sudo flashrom --help

# Test Intel tool
wine intel-platform-flash-tool --help

# Test EMBA
emba -h
```

### Hardware Compatibility Test

```bash
# Check for Intel GbE controller
lspci | grep -i "ethernet.*intel"

# Check for ME device
lspci | grep -i "management\|me"

# Test SPI flash access
sudo flashrom -p internal --list
```

## Troubleshooting

### Common Issues

#### Permission Denied Errors

```bash
# Add user to required groups
sudo usermod -a -G dsmil,kmem $USER

# Re-login or restart session
newgrp dsmil
```

#### flashrom: No programmer found

```bash
# Check kernel modules
lsmod | grep spi
lsmod | grep intel_spi

# Load modules manually
sudo modprobe intel_spi
sudo modprobe spi_intel
```

#### Wine: Application failed to start

```bash
# Reconfigure Wine
winecfg

# Install Visual C++ runtime
winetricks vcrun2019

# Use 32-bit Wine prefix
WINEARCH=win32 winecfg
```

#### GbE NVM: Controller not found

```bash
# Check PCI device
lspci -s 00:1f.6 -nn

# Try different PCI address
GBE_PCI_BDF="0000:00:1f.6" sudo gbe-nvm-update detect
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
export DSMIL_DEBUG=1
export FLASHROM_DEBUG=1

# Run with debug
sudo -E gbe-nvm-update detect
```

### Log Files

Check log files for detailed error information:

```bash
# GbE toolkit logs
tail -f gbe-nvm-toolkit/gbe_nvm.log

# System logs
sudo journalctl -f -t kernel
dmesg | tail -f
```

## Uninstallation

### System-wide Installation

```bash
# Remove installed files
sudo make uninstall

# Remove configuration
sudo rm -rf /etc/dsmil-firmware-toolkit/
sudo rm -f /etc/udev/rules.d/99-dsmil-firmware.rules
sudo rm -f /etc/modules-load.d/dsmil.conf

# Remove user from dsmil group
sudo gpasswd -d $USER dsmil
```

### Manual Installation

```bash
# Remove installation directory
sudo rm -rf /opt/dsmil-firmware-toolkit/

# Remove symlinks
sudo rm -f /usr/local/bin/gbe-nvm-update
sudo rm -f /usr/local/bin/gbe-nvm-mmio
sudo rm -f /usr/local/bin/gbe-nvm-ethtool
sudo rm -f /usr/local/bin/intel-platform-flash-tool
sudo rm -f /usr/local/bin/emba
```

## Next Steps

After successful installation:

1. **Read the documentation** in `docs/` directory
2. **Run basic tests** with `make test`
3. **Check examples** in `examples/` directory
4. **Review security considerations** in `docs/SECURITY.md`

## Support

For installation issues:

- **GitHub Issues**: [Installation Issues](https://github.com/dsmil/firmware-toolkit/issues?q=is%3Aissue+is%3Aopen+label%3Ainstallation)
- **Discussions**: [Installation Help](https://github.com/dsmil/firmware-toolkit/discussions/categories/installation)
- **Documentation**: [Troubleshooting](TROUBLESHOOTING.md)

## Security Notes

⚠️ **Important Security Considerations**:

- This toolkit modifies system firmware
- Always backup firmware before modifications
- Test on non-production systems first
- Ensure proper authorization for firmware modifications
- Review `docs/SECURITY.md` for detailed security guidelines

See the main [README.md](../README.md) for more information about security considerations and proper usage.
