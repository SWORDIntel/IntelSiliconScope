#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2024 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
# SPDX-License-Identifier: GPL-3.0-only
#
# Author(s): DSMIL Integration Team

# Description: Hardware Register Access Analysis Module
# Analyzes hardware register access patterns, MMIO operations, and DMA controls
# Detects potential hardware manipulation capabilities

S126_hardware_register_analysis() {
  module_log_init "${FUNCNAME[0]}"
  module_title "Hardware Register Access Analysis"
  pre_module_reporter "${FUNCNAME[0]}"

  local REGISTER_ACCESS_FOUND=0
  local MMIO_OPERATIONS_FOUND=0
  local DMA_CONTROLS_FOUND=0
  local HARDWARE_BACKDOORS_FOUND=0
  
  export HW_ANALYSIS_DIR="${LOG_PATH_MODULE}/hardware_analysis"
  mkdir -p "${HW_ANALYSIS_DIR}"

  print_output "[*] Analyzing hardware register access patterns..."
  
  # Analyze register access patterns
  analyze_register_access
  
  # Analyze MMIO operations
  analyze_mmio_operations
  
  # Analyze DMA controls
  analyze_dma_controls
  
  # Check for hardware backdoors
  check_hardware_backdoors
  
  # Analyze PCI/PCIe access
  analyze_pci_access
  
  # Analyze memory-mapped devices
  analyze_mmap_devices
  
  # Generate hardware security report
  generate_hardware_report

  write_log ""
  write_log "[*] Statistics:${REGISTER_ACCESS_FOUND}:${MMIO_OPERATIONS_FOUND}:${DMA_CONTROLS_FOUND}:${HARDWARE_BACKDOORS_FOUND}"
  module_end_log "${FUNCNAME[0]}" "${REGISTER_ACCESS_FOUND}"
}

analyze_register_access() {
  print_output "[*] Analyzing register access patterns..."
  
  local REGISTER_PATTERNS=(
    "iowrite32"
    "ioread32"
    "writel"
    "readl"
    "write_register"
    "read_register"
    "CSR_WRITE"
    "CSR_READ"
    "REG_WRITE"
    "REG_READ"
  )
  
  {
    echo "=== Hardware Register Access Analysis ==="
    echo "Analysis Date: $(date)"
    echo ""
    
    for PATTERN in "${REGISTER_PATTERNS[@]}"; do
      echo "[*] Searching for: ${PATTERN}"
      local COUNT=0
      
      while IFS= read -r MATCH; do
        echo "  ${MATCH}"
        ((COUNT++))
        ((REGISTER_ACCESS_FOUND++))
      done < <(grep -r "${PATTERN}" "${FIRMWARE_PATH}" 2>/dev/null | head -20)
      
      echo "  Found: ${COUNT} instances"
      echo ""
    done
    
  } > "${HW_ANALYSIS_DIR}/register_access.txt"
  
  print_output "[+] Register access analysis complete: ${REGISTER_ACCESS_FOUND} patterns found"
}

analyze_mmio_operations() {
  print_output "[*] Analyzing MMIO operations..."
  
  {
    echo "=== Memory-Mapped I/O Analysis ==="
    echo ""
    
    # Check for MMIO mapping functions
    echo "[*] MMIO mapping functions:"
    grep -r "ioremap\|iounmap\|devm_ioremap" "${FIRMWARE_PATH}" 2>/dev/null | head -30
    
    # Check for MMIO access patterns
    echo ""
    echo "[*] MMIO access patterns:"
    grep -r "__iomem\|iowrite\|ioread" "${FIRMWARE_PATH}" 2>/dev/null | head -30
    
    # Check for uncached memory access
    echo ""
    echo "[*] Uncached memory access:"
    grep -r "ioremap_nocache\|ioremap_wc" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Count MMIO operations
    local MMIO_COUNT=$(grep -rc "iowrite\|ioread" "${FIRMWARE_PATH}" 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
    MMIO_OPERATIONS_FOUND=${MMIO_COUNT:-0}
    
  } > "${HW_ANALYSIS_DIR}/mmio_operations.txt"
  
  print_output "[+] MMIO analysis complete: ${MMIO_OPERATIONS_FOUND} operations found"
}

analyze_dma_controls() {
  print_output "[*] Analyzing DMA controls..."
  
  {
    echo "=== DMA Control Analysis ==="
    echo ""
    
    # Check for DMA allocation
    echo "[*] DMA allocation functions:"
    grep -r "dma_alloc\|dma_free\|dma_map\|dma_unmap" "${FIRMWARE_PATH}" 2>/dev/null | head -30
    
    # Check for DMA coherency
    echo ""
    echo "[*] DMA coherency controls:"
    grep -r "dma_sync\|dma_cache" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Check for scatter-gather DMA
    echo ""
    echo "[*] Scatter-gather DMA:"
    grep -r "sg_dma\|dma_map_sg" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Check for DMA streaming
    echo ""
    echo "[*] DMA streaming operations:"
    grep -r "dma_map_single\|dma_unmap_single" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Count DMA controls
    local DMA_COUNT=$(grep -rc "dma_" "${FIRMWARE_PATH}" 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
    DMA_CONTROLS_FOUND=${DMA_COUNT:-0}
    
  } > "${HW_ANALYSIS_DIR}/dma_controls.txt"
  
  print_output "[+] DMA analysis complete: ${DMA_CONTROLS_FOUND} controls found"
}

check_hardware_backdoors() {
  print_output "[*] Checking for hardware backdoor indicators..."
  
  local BACKDOOR_PATTERNS=(
    "hidden.*register"
    "undocumented.*access"
    "secret.*mode"
    "backdoor"
    "debug.*unlock"
    "factory.*unlock"
    "engineering.*unlock"
  )
  
  {
    echo "=== Hardware Backdoor Analysis ==="
    echo ""
    
    for PATTERN in "${BACKDOOR_PATTERNS[@]}"; do
      echo "[*] Checking for: ${PATTERN}"
      
      if grep -ri "${PATTERN}" "${FIRMWARE_PATH}" 2>/dev/null | head -10 >> "${HW_ANALYSIS_DIR}/backdoor_temp.txt"; then
        ((HARDWARE_BACKDOORS_FOUND++))
        echo "[!] SUSPICIOUS: Found pattern '${PATTERN}'"
      fi
      echo ""
    done
    
    # Check for suspicious register sequences
    echo "[*] Checking for suspicious register sequences..."
    grep -r "magic.*value\|magic.*sequence\|unlock.*sequence" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Check for hidden functionality
    echo ""
    echo "[*] Checking for hidden functionality..."
    grep -r "hidden\|secret\|undocumented" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "register\|access\|mode" | head -20
    
  } > "${HW_ANALYSIS_DIR}/hardware_backdoors.txt"
  
  if [[ ${HARDWARE_BACKDOORS_FOUND} -gt 0 ]]; then
    print_output "[!] WARNING: ${HARDWARE_BACKDOORS_FOUND} potential hardware backdoor indicators found"
  fi
}

analyze_pci_access() {
  print_output "[*] Analyzing PCI/PCIe access patterns..."
  
  {
    echo "=== PCI/PCIe Access Analysis ==="
    echo ""
    
    # Check for PCI configuration access
    echo "[*] PCI configuration access:"
    grep -r "pci_read_config\|pci_write_config" "${FIRMWARE_PATH}" 2>/dev/null | head -30
    
    # Check for PCIe capability access
    echo ""
    echo "[*] PCIe capability access:"
    grep -r "pcie_capability\|pci_find_capability" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Check for MSI/MSI-X
    echo ""
    echo "[*] MSI/MSI-X interrupt handling:"
    grep -r "pci_enable_msi\|pci_enable_msix" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Check for PCI power management
    echo ""
    echo "[*] PCI power management:"
    grep -r "pci_set_power_state\|pci_save_state" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
  } > "${HW_ANALYSIS_DIR}/pci_access.txt"
}

analyze_mmap_devices() {
  print_output "[*] Analyzing memory-mapped devices..."
  
  {
    echo "=== Memory-Mapped Device Analysis ==="
    echo ""
    
    # Check for device tree references
    echo "[*] Device tree references:"
    find "${FIRMWARE_PATH}" -name "*.dtb" -o -name "*.dts" 2>/dev/null | head -20
    
    # Check for platform device registration
    echo ""
    echo "[*] Platform device registration:"
    grep -r "platform_device_register\|platform_driver_register" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
    # Check for memory resource allocation
    echo ""
    echo "[*] Memory resource allocation:"
    grep -r "request_mem_region\|ioremap" "${FIRMWARE_PATH}" 2>/dev/null | head -30
    
    # Check for GPIO access
    echo ""
    echo "[*] GPIO access patterns:"
    grep -r "gpio_request\|gpio_set_value\|gpio_get_value" "${FIRMWARE_PATH}" 2>/dev/null | head -20
    
  } > "${HW_ANALYSIS_DIR}/mmap_devices.txt"
}

generate_hardware_report() {
  print_output "[*] Generating hardware security report..."
  
  {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Hardware Register Access Security Report              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Analysis Date: $(date)"
    echo "Firmware Path: ${FIRMWARE_PATH}"
    echo ""
    echo "=== Summary Statistics ==="
    echo "Register Access Patterns: ${REGISTER_ACCESS_FOUND}"
    echo "MMIO Operations: ${MMIO_OPERATIONS_FOUND}"
    echo "DMA Controls: ${DMA_CONTROLS_FOUND}"
    echo "Potential Backdoors: ${HARDWARE_BACKDOORS_FOUND}"
    echo ""
    echo "=== Security Assessment ==="
    
    if [[ ${HARDWARE_BACKDOORS_FOUND} -gt 0 ]]; then
      echo "[!] CRITICAL: Potential hardware backdoor indicators detected"
      echo "    Priority: IMMEDIATE INVESTIGATION REQUIRED"
      echo "    - Review all suspicious patterns in detail"
      echo "    - Verify legitimacy of undocumented features"
      echo "    - Check for unauthorized hardware access"
    fi
    
    if [[ ${REGISTER_ACCESS_FOUND} -gt 100 ]]; then
      echo "[!] WARNING: Extensive register access detected"
      echo "    - Review register access controls"
      echo "    - Ensure proper access validation"
      echo "    - Audit register write operations"
    fi
    
    if [[ ${MMIO_OPERATIONS_FOUND} -gt 50 ]]; then
      echo "[!] INFO: Significant MMIO usage detected"
      echo "    - Verify MMIO mappings are secure"
      echo "    - Check for proper memory barriers"
      echo "    - Ensure uncached access is necessary"
    fi
    
    if [[ ${DMA_CONTROLS_FOUND} -gt 30 ]]; then
      echo "[!] INFO: DMA operations detected"
      echo "    - Verify DMA buffer security"
      echo "    - Check for DMA coherency issues"
      echo "    - Ensure proper DMA cleanup"
    fi
    
    echo ""
    echo "=== Detailed Analysis Files ==="
    ls -lh "${HW_ANALYSIS_DIR}/" 2>/dev/null
    echo ""
    echo "=== Recommendations ==="
    echo "1. Review all hardware access patterns for legitimacy"
    echo "2. Audit register write operations for security issues"
    echo "3. Verify MMIO mappings use proper access controls"
    echo "4. Check DMA operations for buffer overflow vulnerabilities"
    echo "5. Investigate any suspicious or undocumented features"
    echo "6. Test hardware security controls in runtime environment"
    echo "7. Document all hardware access mechanisms"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Examine individual analysis files in ${HW_ANALYSIS_DIR}"
    echo "2. Correlate findings with WiFi firmware analysis"
    echo "3. Test hardware access controls in live environment"
    echo "4. Document remediation steps for identified issues"
    
  } > "${HW_ANALYSIS_DIR}/HARDWARE_SECURITY_REPORT.txt"
  
  print_output "[+] Hardware security report generated"
  print_output "[+] Report location: ${HW_ANALYSIS_DIR}/HARDWARE_SECURITY_REPORT.txt"
}
