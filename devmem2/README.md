# devmem2 - Enhanced Memory Access Tool for DSMIL

Enhanced version of devmem2 for Intel hardware probing and MMIO register access in the DSMIL system.

## Original

Original devmem2 by Jan-Derk Bakker (jdb@lartmaker.nl) - Simple program to read/write from/to any location in memory.

## Enhancements for DSMIL

This enhanced version adds:

- **Parse-friendly output mode** (`-p`) - Optimized for script parsing
- **Batch mode** (`-b`) - Read multiple addresses in one command
- **Range mode** (`-r`) - Read a range of addresses
- **64-bit support** (`d` type) - Read/write 64-bit dwords
- **Quiet mode** (`-q`) - Minimal output for scripting
- **Verbose mode** (`-v`) - Detailed debugging output
- **Better error handling** - Clear error messages
- **Decimal output option** (`-d`) - Output in decimal instead of hex

## Building

```bash
cd tools/devmem2
make
```

## Installation

```bash
sudo make install
```

Or copy the binary manually:
```bash
sudo cp devmem2 /usr/local/bin/
```

## Usage

### Basic Usage

```bash
# Read 32-bit word (default)
./devmem2 0x10000000 w

# Write 32-bit word
./devmem2 0x10000000 w 0x12345678

# Read byte
./devmem2 0x10000000 b

# Read 64-bit dword
./devmem2 0x10000000 d
```

### Enhanced Features

```bash
# Parse-friendly output (for scripts)
./devmem2 -p 0x10000000 w
# Output: Read 0x12345678

# Batch read multiple addresses
./devmem2 -b 0x10000000 0x10000004 0x10000008 w

# Read range of addresses
./devmem2 -r 0x10000000 0x1000000F

# Quiet mode (minimal output)
./devmem2 -q 0x10000000 w
# Output: 0x12345678

# Verbose mode (detailed output)
./devmem2 -v 0x10000000 w

# Decimal output
./devmem2 -d 0x10000000 w
```

## Integration with DSMIL Hardware Probing

The `dsmil_hardware.sh` script uses devmem2 for MMIO register reads:

```bash
# Script expects output format: "Read 0x..."
devmem2 -p 0x10000000 w
```

The parse mode (`-p`) is specifically designed for this integration.

## Access Types

- `b` - Byte (8-bit)
- `h` - Halfword (16-bit)
- `w` - Word (32-bit, default)
- `d` - Dword (64-bit)

## Requirements

- Root privileges (access to `/dev/mem`)
- Linux kernel with `/dev/mem` support
- GCC compiler

## Security Note

This tool provides direct access to physical memory. Use with caution and only on systems you own or have explicit permission to access.

## License

GPL-2.0 (same as original)
