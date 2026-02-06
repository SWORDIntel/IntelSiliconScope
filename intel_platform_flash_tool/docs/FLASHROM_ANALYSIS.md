# flashrom Analysis Results

## Chipset Detection

**Chipset**: Intel Meteor Lake-P/M  
**flashrom Version**: 1.4.0  
**Status**: Detected successfully

## Flash Region Analysis

### Region Mapping (from flashrom)

**FREG0**: Flash Descriptor region
- Address: `0x00000000-0x00003fff` (16KB)
- Access: **Read-only**
- Purpose: Flash descriptor, region definitions

**FREG1**: BIOS region
- Address: `0x02000000-0x03ffffff` (32MB)
- Access: **Read-write**
- Purpose: BIOS/UEFI firmware

**FREG2**: Management Engine region
- Address: `0x00126000-0x00ec7fff` (~14.5MB)
- Access: **Read-only**
- Purpose: ME firmware

**FREG3**: Gigabit Ethernet region
- Address: `0x00124000-0x00125fff` (8KB)
- Access: **Read-write**
- Purpose: GbE firmware

**FREG8**: EC/BMC region
- Address: `0x00004000-0x00123fff` (~1.1MB)
- Access: **Locked**
- Purpose: Embedded Controller/BMC firmware

**FREG9**: Device Expansion 2 region
- Address: `0x00ec8000-0x01ffffff` (~19MB)
- Access: **Read-only**
- Purpose: Additional device firmware

## Important Findings

### ME Region Discrepancy

**flashrom reports**: ME region at `0x00126000-0x00ec7fff`  
**Kernel module found**: ME region at `0x02000000-0x03FFF000` (from FREG1 register)

**Analysis**:
- flashrom's FREG2 shows ME at `0x00126000-0x00ec7fff` (read-only)
- Kernel module's FREG1 shows `0x02000000-0x03FFF000` (which flashrom calls BIOS region)
- This suggests the ME firmware may be embedded within the BIOS region
- Or the FREG1 register interpretation differs between tools

### Access Restrictions

**Read Protection**:
- ME region (FREG2) is **read-only** via flashrom
- Flash descriptor (FREG0) is **read-only**
- EC/BMC region (FREG8) is **locked**

**Write Protection**:
- BIOS region (FREG1) is read-write
- GbE region (FREG3) is read-write
- ME region (FREG2) is read-only (cannot write)

### ME Active Status

flashrom reports:
> "Not all flash regions are freely accessible by flashrom. This is most likely due to an active ME."

This confirms the ME is active and protecting certain regions.

## Recommendations

### For ME Firmware Dumping

1. **Try reading ME region directly**:
   ```bash
   sudo flashrom -p internal:laptop=this_is_not_a_laptop -r me_dump.bin -i FREG2
   ```

2. **Read entire flash and extract ME**:
   ```bash
   # Read full flash (may fail due to protection)
   sudo flashrom -p internal:laptop=this_is_not_a_laptop -r full_flash.bin
   
   # Extract ME region (0x00126000-0x00ec7fff)
   dd if=full_flash.bin of=me_region.bin bs=1 skip=$((0x00126000)) count=$((0x00DB5FFF))
   ```

3. **Use kernel module for register access**:
   - Kernel module can read SPI controller registers directly
   - May bypass some flashrom restrictions
   - Stage 5 already provides FRAP and FREG1 values

### For HAP Bit Analysis

1. **If ME region is at 0x00126000-0x00ec7fff**:
   - ME header: `0x00126000 + 0x10-0x20`
   - ME config: `0x00126000 + 0x1000-0x2000`

2. **If ME is embedded in BIOS region (0x02000000-0x03ffffff)**:
   - Need to analyze BIOS image to find ME partition
   - ME may be at offset within BIOS region

3. **Use both tools**:
   - flashrom for full flash dump
   - Kernel module for direct register access
   - Compare results to identify correct ME location

## Next Steps

1. ✅ flashrom installed and chipset detected
2. ⏳ Attempt full flash read (may be restricted)
3. ⏳ Extract ME region from dump
4. ⏳ Analyze ME firmware for HAP bit location
5. ⏳ Compare flashrom and kernel module findings

## Safety Notes

- ME region is **read-only** - safe to read
- **Do not attempt to write** ME region without proper tools and knowledge
- Always backup full flash before any modifications
- HAP bit modification requires specialized tools (Intel Flash Image Tool, MEConfig)
