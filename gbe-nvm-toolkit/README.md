# Intel GbE NVM Update Toolkit - Linux Native

Linux-native replacement for `UpdateIntelGbENVMW64e_v1.0.10_ZPE.exe`.

Replaces the Windows `iQVW64.SYS` diagnostic driver approach with native Linux tools:
- **flashrom** — SPI flash read/write (GbE region at 0x124000)
- **MMIO** — Direct register access via `/dev/mem`
- **ethtool** — Driver-level EEPROM access (when e1000e is loaded)

## Tools

| Tool | Method | Root? | Driver Needed? |
|------|--------|-------|----------------|
| `gbe_nvm_update.sh` | flashrom + python | Yes | No |
| `gbe_nvm_mmio.py` | Direct MMIO `/dev/mem` | Yes | No |
| `gbe_nvm_ethtool.sh` | ethtool -e/-E | Yes | Yes (e1000e) |

## Quick Start

```bash
# Make executable
chmod +x gbe_nvm_update.sh gbe_nvm_mmio.py gbe_nvm_ethtool.sh

# Detect controller
./gbe_nvm_update.sh detect

# Read current NVM from SPI
sudo ./gbe_nvm_update.sh read backup.bin

# Show NVM image info
./gbe_nvm_update.sh info backup.bin

# Validate checksum
./gbe_nvm_update.sh verify backup.bin

# Fix checksum
./gbe_nvm_update.sh fixsum image.bin

# Set MAC address (auto-fixes checksum)
./gbe_nvm_update.sh setmac image.bin DE:11:54:50:99:69

# Generate default NVM image
./gbe_nvm_update.sh generate default.bin DE:11:54:50:99:69 15FC

# Flash NVM to SPI
sudo ./gbe_nvm_update.sh write image.bin

# Full restore procedure (backup → validate → flash → verify → reload)
sudo ./gbe_nvm_update.sh restore

# Reload e1000e driver
sudo ./gbe_nvm_update.sh reload
```

## MMIO Direct Access

When flashrom isn't available or you need register-level access:

```bash
# Check controller status
sudo python3 gbe_nvm_mmio.py status

# Read MAC from NVM registers
sudo python3 gbe_nvm_mmio.py mac

# Read NVM via EERD register
sudo python3 gbe_nvm_mmio.py read nvm_dump.bin

# Write NVM via EEWR register
sudo python3 gbe_nvm_mmio.py write nvm_image.bin
```

## ethtool Access

When the e1000e driver is loaded and bound:

```bash
# Show EEPROM info
./gbe_nvm_ethtool.sh enp0s31f6 info

# Dump full EEPROM
./gbe_nvm_ethtool.sh enp0s31f6 dump eeprom.bin
```

## NVM Checksum

Intel GbE NVM uses 0xBABA checksum: sum of first 64 words (128 bytes) must equal 0xBABA.

## Flash Region Layout

```
SPI Flash:
  0x000000 - 0x003FFF  Flash Descriptor (16KB)
  0x004000 - 0x123FFF  EC/BMC (~1.1MB)
  0x124000 - 0x125FFF  GbE NVM (8KB) ← THIS TOOLKIT
  0x126000 - 0xEC7FFF  ME Firmware (~14.5MB)
  0x2000000+            BIOS/UEFI (32MB)
```

## Controller Support

- Intel I219-V (15FC) — Meteor Lake
- Intel I219-LM (15D7) — Meteor Lake
- Intel I218-V/LM
- Intel I217-V/LM
- Any e1000e family controller

## Dependencies

- `flashrom` (for SPI flash access)
- `python3` (for checksum/NVM operations)
- `ethtool` (optional, for driver-level access)

## Original Windows Tool

The original `UpdateIntelGbENVMW64e_v1.0.10_ZPE.exe` is a self-extracting archive containing:
- `Setup.exe` — PE32+ console app (Intel GbE NVM updater)
- `iQVW64.SYS` — Intel diagnostic driver for direct NVM access

This Linux toolkit provides equivalent functionality using native methods.
