#!/usr/bin/env python3
"""
Advanced HAP Bit Finder for ME Firmware
Searches for HAP bit location using multiple methods
"""

import sys
import struct
import re
from pathlib import Path

# Known ME firmware structures
ME_HEADER_MAGIC = [
    b'\x24\x00\x00\x00',  # ME header magic (possible)
    b'$ME',               # ME signature
    b'MEFW',              # ME Firmware
    b'\x01\x00\x00\x00',  # Version 1
]

# HAP bit is typically in:
# 1. ME firmware header (offset 0x10-0x20) - flags/status word
# 2. ME configuration region (offset 0x1000-0x2000) - config flags
# 3. HFSTS1 register location (if stored in firmware)

# Current HFSTS1 value: 0x94000245
# HAP bit is bit 12 (0x1000)
# Current value has bit 12 = 0 (HAP disabled)

def find_me_header(data):
    """Find ME firmware header"""
    print("=" * 70)
    print("SEARCHING FOR ME FIRMWARE HEADER")
    print("=" * 70)
    print()
    
    # Look for ME magic/signature
    for magic in ME_HEADER_MAGIC:
        offset = data.find(magic)
        if offset != -1:
            print(f"✓ Found potential ME header magic '{magic}' at offset 0x{offset:08X}")
            
            # Show context
            context_start = max(0, offset - 16)
            context_end = min(len(data), offset + 256)
            context = data[context_start:context_end]
            
            print(f"Context (offset 0x{context_start:08X}):")
            for i in range(0, min(256, len(context)), 16):
                rel_offset = context_start + i
                hex_str = ' '.join(f'{b:02X}' for b in context[i:i+16])
                ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in context[i:i+16])
                marker = " <-- MAGIC" if context_start + i <= offset < context_start + i + 16 else ""
                print(f"  {rel_offset:08X}: {hex_str:<48} {ascii_str}{marker}")
            print()
            return offset
    
    print("⚠ ME header magic not found")
    print("  Trying to analyze first 256 bytes as header...")
    print()
    return 0

def analyze_hap_bit_candidates(data, header_offset=0):
    """Analyze potential HAP bit locations"""
    print("=" * 70)
    print("HAP BIT CANDIDATE ANALYSIS")
    print("=" * 70)
    print()
    
    # Method 1: Check header flags (offset 0x10-0x20 from header)
    print("Method 1: Header Flags Region (offset 0x10-0x20 from header)")
    header_flags_start = header_offset + 0x10
    header_flags_end = header_offset + 0x30
    
    if header_flags_end <= len(data):
        flags_data = data[header_flags_start:header_flags_end]
        print(f"Analyzing offset 0x{header_flags_start:08X}-0x{header_flags_end:08X}:")
        
        for i in range(0, len(flags_data), 4):
            if i + 4 <= len(flags_data):
                offset = header_flags_start + i
                value = struct.unpack('<I', flags_data[i:i+4])[0]
                
                # Check for HAP bit (bit 12 = 0x1000)
                has_hap_bit = (value & 0x1000) != 0
                # Check for other interesting bits
                has_interesting_bits = (value & 0xFFFF) != 0
                
                if has_interesting_bits:
                    print(f"  Offset 0x{offset:08X}: 0x{value:08X} ", end="")
                    if has_hap_bit:
                        print("✓ BIT 12 SET (potential HAP bit)")
                    else:
                        print("(bit 12 clear)")
        print()
    
    # Method 2: Configuration region (offset 0x1000-0x2000)
    print("Method 2: Configuration Region (offset 0x1000-0x2000)")
    config_start = 0x1000
    config_end = 0x2000
    
    if config_end <= len(data):
        config_data = data[config_start:config_end]
        print(f"Analyzing offset 0x{config_start:08X}-0x{config_end:08X}:")
        
        # Look for values that might be HAP-related
        # HAP bit patterns: bit 12 set, but also check for known values
        hap_candidates = []
        
        for i in range(0, len(config_data), 4):
            if i + 4 <= len(config_data):
                offset = config_start + i
                value = struct.unpack('<I', config_data[i:i+4])[0]
                
                # Check for HAP bit (bit 12)
                if value & 0x1000:
                    # Check if it's not just a data pattern
                    # HAP bit should be in a flags/status word, not in data arrays
                    # Look for values that might be flags (not just incrementing patterns)
                    if value != 0 and value != 0xFFFFFFFF:
                        hap_candidates.append((offset, value))
        
        # Filter out obvious data patterns (like 0x00C01003, 0x00C03003 sequence)
        # Keep only unique or interesting values
        unique_candidates = []
        seen_values = set()
        for offset, value in hap_candidates:
            # Skip if it's part of an incrementing pattern
            if value not in seen_values:
                seen_values.add(value)
                unique_candidates.append((offset, value))
        
        if unique_candidates:
            print(f"  Found {len(unique_candidates)} unique HAP bit candidates:")
            for offset, value in unique_candidates[:20]:  # Show first 20
                print(f"    Offset 0x{offset:08X}: 0x{value:08X} (bit 12 set)")
            if len(unique_candidates) > 20:
                print(f"    ... and {len(unique_candidates) - 20} more")
        else:
            print("  ⚠ No unique HAP bit candidates found (may be data patterns)")
        print()
    
    # Method 3: Search for HFSTS1-related structures
    print("Method 3: HFSTS1 Register Location")
    # HFSTS1 = 0x94000245 (current value)
    # HAP bit should be 0 in current value
    # If we find this value, the HAP bit location would be nearby
    
    hfsts1_value = 0x94000245
    hfsts1_bytes = struct.pack('<I', hfsts1_value)
    
    offset = data.find(hfsts1_bytes)
    if offset != -1:
        print(f"✓ Found HFSTS1 value (0x94000245) at offset 0x{offset:08X}")
        print(f"  HAP bit location would be at this offset (bit 12 of this word)")
        print(f"  To enable HAP: Set bit 12 (0x1000) -> 0x{hfsts1_value | 0x1000:08X}")
        print()
        
        # Show context
        context_start = max(0, offset - 32)
        context_end = min(len(data), offset + 36)
        context = data[context_start:context_end]
        
        print("Context around HFSTS1:")
        for i in range(0, len(context), 16):
            rel_offset = context_start + i
            hex_str = ' '.join(f'{b:02X}' for b in context[i:i+16])
            ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in context[i:i+16])
            marker = " <-- HFSTS1" if context_start + i <= offset < context_start + i + 16 else ""
            print(f"  {rel_offset:08X}: {hex_str:<48} {ascii_str}{marker}")
    else:
        print("⚠ HFSTS1 value not found in firmware")
        print("  HFSTS1 is likely a runtime register, not stored in firmware")
    print()
    
    # Method 4: Look for HAP command (0x85FF)
    print("Method 4: HAP Command Pattern (0x85FF)")
    hap_cmd = struct.pack('<H', 0x85FF)  # HAP override command
    hap_cmd_rev = struct.pack('>H', 0x85FF)  # Big-endian
    
    for cmd_bytes, endian in [(hap_cmd, 'little'), (hap_cmd_rev, 'big')]:
        offset = data.find(cmd_bytes)
        if offset != -1:
            print(f"✓ Found HAP command (0x85FF, {endian}-endian) at offset 0x{offset:08X}")
            
            # Show context
            context_start = max(0, offset - 16)
            context_end = min(len(data), offset + 32)
            context = data[context_start:context_end]
            
            print("Context:")
            for i in range(0, len(context), 16):
                rel_offset = context_start + i
                hex_str = ' '.join(f'{b:02X}' for b in context[i:i+16])
                ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in context[i:i+16])
                marker = " <-- HAP CMD" if context_start + i <= offset < context_start + i + 16 else ""
                print(f"  {rel_offset:08X}: {hex_str:<48} {ascii_str}{marker}")
            print()
    
    print()

def main():
    if len(sys.argv) < 2:
        print("Usage: find_hap_bit.py <me_firmware_dump.bin>")
        print()
        print("Advanced HAP bit location finder for ME firmware")
        sys.exit(1)
    
    dump_file = Path(sys.argv[1])
    
    if not dump_file.exists():
        print(f"Error: File not found: {dump_file}")
        sys.exit(1)
    
    print("=" * 70)
    print("ADVANCED HAP BIT FINDER")
    print("=" * 70)
    print(f"File: {dump_file}")
    print(f"Size: {dump_file.stat().st_size} bytes ({dump_file.stat().st_size / 1024 / 1024:.2f} MB)")
    print("=" * 70)
    print()
    
    # Read ME firmware dump
    with open(dump_file, 'rb') as f:
        data = f.read()
    
    if len(data) == 0:
        print("Error: ME firmware dump is empty")
        sys.exit(1)
    
    # Check if dump is all zeros
    if all(b == 0 for b in data[:1024]):
        print("⚠ Warning: First 1KB is all zeros")
        print("  Dump may not have been read correctly")
        print()
    
    # Find ME header
    header_offset = find_me_header(data)
    
    # Analyze HAP bit candidates
    analyze_hap_bit_candidates(data, header_offset)
    
    print("=" * 70)
    print("ANALYSIS COMPLETE")
    print("=" * 70)
    print()
    print("Summary:")
    print("- HAP bit is bit 12 (0x1000) in a 32-bit word")
    print("- Current HFSTS1: 0x94000245 (HAP bit = 0, disabled)")
    print("- To enable HAP: Set bit 12 -> 0x94001245")
    print("- HAP bit location in firmware may be:")
    print("  1. ME header flags (offset 0x10-0x20)")
    print("  2. ME configuration region (offset 0x1000-0x2000)")
    print("  3. Runtime register (not in firmware)")
    print()

if __name__ == '__main__':
    main()
