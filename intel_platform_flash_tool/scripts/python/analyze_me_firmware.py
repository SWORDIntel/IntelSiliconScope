#!/usr/bin/env python3
"""
ME Firmware Analyzer - Find HAP Bit Location
Analyzes ME firmware dump to locate HAP (High Assurance Platform) bit
"""

import sys
import struct
import re
from pathlib import Path

# ME Firmware Version: 0:18.0.18.2571
ME_VERSION = "18.0.18.2571"

# Known HAP bit patterns and locations
HAP_PATTERNS = [
    b'HAP',
    b'High Assurance',
    b'HAP Mode',
    b'HAP_OVERRIDE',
    b'0x85FF',  # HAP override command
    b'HFSTS1',
    b'\x85\xFF',  # HAP command bytes
]

# ME firmware header structure (typical)
# Offset 0x00-0x0F: Signature/Magic
# Offset 0x10-0x1F: Version info
# Offset 0x20-0x2F: Flags/Status
# Offset 0x30-0x3F: Configuration

def analyze_me_header(data):
    """Analyze ME firmware header (first 256 bytes)"""
    print("=" * 70)
    print("ME FIRMWARE HEADER ANALYSIS")
    print("=" * 70)
    print()
    
    if len(data) < 256:
        print(f"⚠ Warning: Data too short ({len(data)} bytes), expected at least 256 bytes")
        return
    
    # Check for ME signature/magic
    print("Header (first 64 bytes):")
    for i in range(0, min(64, len(data)), 16):
        hex_str = ' '.join(f'{b:02X}' for b in data[i:i+16])
        ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[i:i+16])
        print(f"  {i:04X}: {hex_str:<48} {ascii_str}")
    print()
    
    # Look for version string
    version_match = re.search(rb'(\d+\.\d+\.\d+\.\d+)', data[:1024])
    if version_match:
        print(f"✓ Found version string: {version_match.group(1).decode('ascii', errors='ignore')}")
    print()
    
    # Check for HAP-related patterns in header
    print("Searching for HAP patterns in header...")
    found_patterns = []
    for pattern in HAP_PATTERNS:
        offset = data.find(pattern)
        if offset != -1 and offset < 1024:
            found_patterns.append((offset, pattern))
            print(f"  ✓ Found '{pattern.decode('ascii', errors='ignore')}' at offset 0x{offset:04X}")
    print()
    
    # Analyze configuration region (offset 0x1000-0x2000)
    if len(data) >= 0x2000:
        print("Analyzing configuration region (0x1000-0x2000)...")
        config_data = data[0x1000:0x2000]
        
        # Look for HAP bit patterns
        for pattern in HAP_PATTERNS:
            offset = config_data.find(pattern)
            if offset != -1:
                abs_offset = 0x1000 + offset
                print(f"  ✓ Found '{pattern.decode('ascii', errors='ignore')}' at offset 0x{abs_offset:04X}")
        
        # Look for bit patterns that might be HAP bit
        # HAP bit is typically bit 12 in HFSTS1 register
        # Look for bytes with bit 12 set (0x10 = bit 4, but we need bit 12 = 0x1000)
        print()
        print("Checking for potential HAP bit locations (bit 12 patterns)...")
        for i in range(0, min(0x1000, len(config_data)), 4):
            if i + 4 <= len(config_data):
                value = struct.unpack('<I', config_data[i:i+4])[0]
                # Check if bit 12 is set (0x1000)
                if value & 0x1000:
                    abs_offset = 0x1000 + i
                    print(f"  ⚠ Potential HAP bit at offset 0x{abs_offset:04X}: 0x{value:08X} (bit 12 set)")
    print()

def search_hap_patterns(data):
    """Search entire ME firmware for HAP-related patterns"""
    print("=" * 70)
    print("FULL ME FIRMWARE SEARCH")
    print("=" * 70)
    print()
    
    print(f"Searching {len(data)} bytes for HAP-related patterns...")
    print()
    
    found_locations = []
    
    for pattern in HAP_PATTERNS:
        matches = []
        start = 0
        while True:
            offset = data.find(pattern, start)
            if offset == -1:
                break
            matches.append(offset)
            start = offset + 1
        
        if matches:
            print(f"Pattern '{pattern.decode('ascii', errors='ignore')}' found {len(matches)} times:")
            for offset in matches[:10]:  # Show first 10 matches
                # Show context
                context_start = max(0, offset - 16)
                context_end = min(len(data), offset + len(pattern) + 16)
                context = data[context_start:context_end]
                
                hex_str = ' '.join(f'{b:02X}' for b in context)
                print(f"  Offset 0x{offset:08X}: {hex_str}")
            if len(matches) > 10:
                print(f"  ... and {len(matches) - 10} more matches")
            print()
            found_locations.extend(matches)
    
    if not found_locations:
        print("⚠ No HAP-related patterns found in ME firmware")
        print("  This may indicate:")
        print("  - ME firmware is encrypted/compressed")
        print("  - HAP bit is stored in a different format")
        print("  - HAP bit location is in a different region")
    print()
    
    return found_locations

def analyze_hfsts1_location(data):
    """Try to locate HFSTS1 register value in ME firmware"""
    print("=" * 70)
    print("HFSTS1 REGISTER SEARCH")
    print("=" * 70)
    print()
    print("HFSTS1 is the ME Firmware Status register (bit 12 = HAP mode)")
    print("Current HFSTS1 value from system: 0x94000245")
    print("HAP bit (bit 12) should be 0 in current value")
    print()
    
    # Search for HFSTS1 value pattern
    hfsts1_value = 0x94000245
    hfsts1_bytes = struct.pack('<I', hfsts1_value)
    
    offset = data.find(hfsts1_bytes)
    if offset != -1:
        print(f"✓ Found HFSTS1 value (0x94000245) at offset 0x{offset:08X}")
        print(f"  This might be where HFSTS1 is stored in ME firmware")
        print()
        
        # Check surrounding bytes
        context_start = max(0, offset - 32)
        context_end = min(len(data), offset + 36)
        context = data[context_start:context_end]
        
        print("Context around HFSTS1 value:")
        for i in range(0, len(context), 16):
            rel_offset = context_start + i
            hex_str = ' '.join(f'{b:02X}' for b in context[i:i+16])
            ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in context[i:i+16])
            marker = " <-- HFSTS1" if context_start + i <= offset < context_start + i + 16 else ""
            print(f"  {rel_offset:08X}: {hex_str:<48} {ascii_str}{marker}")
        print()
    else:
        print("⚠ HFSTS1 value (0x94000245) not found in ME firmware")
        print("  This may indicate:")
        print("  - HFSTS1 is a runtime register, not stored in firmware")
        print("  - ME firmware is encrypted/compressed")
        print("  - HFSTS1 is calculated dynamically")
    print()

def main():
    if len(sys.argv) < 2:
        print("Usage: analyze_me_firmware.py <me_firmware_dump.bin>")
        print()
        print("Analyzes ME firmware dump to locate HAP bit")
        print("ME Region: 0x00126000-0x00EC7FFF (FREG2)")
        sys.exit(1)
    
    dump_file = Path(sys.argv[1])
    
    if not dump_file.exists():
        print(f"Error: File not found: {dump_file}")
        sys.exit(1)
    
    print("=" * 70)
    print("ME FIRMWARE ANALYZER")
    print("=" * 70)
    print(f"File: {dump_file}")
    print(f"Size: {dump_file.stat().st_size} bytes ({dump_file.stat().st_size / 1024 / 1024:.2f} MB)")
    print(f"ME Version: {ME_VERSION}")
    print("=" * 70)
    print()
    
    # Read ME firmware dump
    with open(dump_file, 'rb') as f:
        data = f.read()
    
    if len(data) == 0:
        print("Error: ME firmware dump is empty (all zeros)")
        print("  The dump may not have been read correctly")
        print("  ME region may be protected or encrypted")
        sys.exit(1)
    
    # Check if dump is all zeros
    if all(b == 0 for b in data[:1024]):
        print("⚠ Warning: First 1KB of dump is all zeros")
        print("  This may indicate:")
        print("  - ME region was not read correctly")
        print("  - ME region is protected/encrypted")
        print("  - ME firmware is compressed")
        print()
        print("Attempting analysis anyway...")
        print()
    
    # Analyze ME firmware
    analyze_me_header(data)
    analyze_hfsts1_location(data)
    hap_locations = search_hap_patterns(data)
    
    print("=" * 70)
    print("ANALYSIS COMPLETE")
    print("=" * 70)
    print()
    print("Next steps:")
    print("1. If HAP patterns found, analyze those locations")
    print("2. Check ME firmware documentation for HAP bit location")
    print("3. Use Intel Flash Image Tool or MEConfig for detailed analysis")
    print("4. HAP bit is typically in:")
    print("   - ME firmware header (offset 0x10-0x20)")
    print("   - ME configuration region (offset 0x1000-0x2000)")
    print("   - HFSTS1 register (runtime, not in firmware)")
    print()

if __name__ == '__main__':
    main()
