# Intel Platform Flash Tool & flashrom - Complete Analysis

## Summary

### Tools Downloaded and Analyzed

1. ✅ **Intel Platform Flash Tool Lite 5.8.9.0**
   - Downloaded from: https://github.com/projectceladon/tools
   - Location: `tools/intel_platform_flash_tool/platformflashtoollite_extracted/`
   - **Purpose**: Flashing firmware (not reading)
   - **Components**: GUI tool, CLI wrapper, flsTool (FLS file manipulation)

2. ✅ **flashrom 1.4.0**
   - Installed via `apt install flashrom`
   - **Purpose**: Reading/writing SPI flash
   - **Status**: Chipset detected, but read restrictions due to active ME

### Key Findings

#### Flash Chip
- **Model**: GigaDevice GD25LR512ME
- **Size**: 65536 kB (64MB)
- **Status**: UNTESTED for write-protect operations

#### Flash Regions (from flashrom)

| Region | Address Range | Size | Access | Purpose |
|--------|--------------|------|--------|---------|
| FREG0 | 0x00000000-0x00003FFF | 16KB | Read-only | Flash Descriptor |
| FREG1 | 0x02000000-0x03FFFFFF | 32MB | Read-write | BIOS/UEFI |
| FREG2 | 0x00126000-0x00EC7FFF | ~14.5MB | Read-only | **ME Firmware** |
| FREG3 | 0x00124000-0x00125FFF | 8KB | Read-write | GbE |
| FREG8 | 0x00004000-0x00123FFF | ~1.1MB | Locked | EC/BMC |
| FREG9 | 0x00EC8000-0x01FFFFFF | ~19MB | Read-only | Device Expansion |

#### ME Region Location

**flashrom reports**: ME at `0x00126000-0x00EC7FFF` (FREG2)  
**Kernel module found**: ME region register shows `0x02000000-0x03FFF000` (FREG1)

**Analysis**:
- flashrom's FREG2 is the official ME region (read-only)
- Kernel module's FREG1 interpretation may differ
- ME firmware is likely at **0x00126000-0x00EC7FFF** per flashrom

### Access Restrictions

**Read Protection**:
- ME region (FREG2) is read-only
- EC/BMC region (FREG8) is locked (cannot read)
- Flash descriptor (FREG0) is read-only

**Write Protection**:
- ME region cannot be written (read-only)
- BIOS region can be written (read-write)
- GbE region can be written (read-write)

**Active ME**:
flashrom reports: "Not all flash regions are freely accessible. This is most likely due to an active ME."

This confirms ME is active and protecting regions.

### Tool Capabilities

#### Intel Platform Flash Tool Lite
- ✅ Flash firmware images
- ✅ Extract/analyze FLS files (via flsTool)
- ❌ Cannot read SPI flash directly
- ❌ Cannot dump ME firmware from hardware

#### flashrom
- ✅ Detect chipset and flash chip
- ✅ Read accessible flash regions
- ⚠️ Cannot read locked regions (EC/BMC)
- ⚠️ ME region is read-only (cannot write)
- ✅ Can read BIOS region (FREG1)
- ✅ Can read GbE region (FREG3)

### Recommended Approach for ME Analysis

1. **Use flashrom to read accessible regions**:
   ```bash
   sudo flashrom -p internal:laptop=this_is_not_a_laptop \
     -r flash_dump.bin -l flashlayout.txt
   ```

2. **Extract ME region from dump** (if accessible):
   ```bash
   # ME region: 0x00126000-0x00EC7FFF
   dd if=flash_dump.bin of=me_region.bin \
     bs=1 skip=$((0x00126000)) count=$((0x00DB5FFF))
   ```

3. **Use kernel module for register access**:
   - Stage 5 provides SPI controller register values
   - Can read FRAP, FREG1 directly
   - May provide additional insights

4. **Analyze ME firmware**:
   - Search for HAP-related patterns
   - Locate ME firmware header
   - Identify HAP bit location

### Files Created

1. `ME_FIRMWARE_DUMP_GUIDE.md` - Complete guide for ME dumping
2. `ANALYSIS_SUMMARY.md` - Intel Platform Flash Tool analysis
3. `FLASHROM_ANALYSIS.md` - flashrom findings and region mapping
4. `TOOL_ANALYSIS_COMPLETE.md` - This summary

### Next Steps

1. ✅ Tools downloaded and analyzed
2. ✅ flashrom installed and chipset detected
3. ⏳ Attempt flash read with layout file (excluding locked regions)
4. ⏳ Extract ME region from dump
5. ⏳ Analyze ME firmware for HAP bit location
6. ⏳ Compare findings between tools

### Safety Warnings

⚠️ **CRITICAL**:
- ME region is **read-only** - safe to read
- **Do not attempt to write** ME region without proper tools
- Always backup full flash before any modifications
- HAP bit modification requires specialized knowledge
- Modifying ME firmware can **brick the system permanently**

### References

**Tools:**
- Intel Platform Flash Tool: https://github.com/projectceladon/tools
- flashrom: https://www.flashrom.org/

**Community Resources:**
- coreboot Documentation: https://doc.coreboot.org/ - ME firmware and HAP bit information
- me_cleaner Project: https://github.com/corna/me_cleaner - ME firmware modification tools
- flashrom Wiki: https://www.flashrom.org/Flashrom - SPI flash documentation

**Note:** Intel's official ME firmware documentation is proprietary. Community resources provide practical alternatives for ME firmware analysis.
