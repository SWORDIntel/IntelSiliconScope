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

# Description: WiFi Firmware Analysis Module
# Analyzes WiFi firmware, drivers, and hardware configurations
# Detects engineering modes, register access, and security bypasses

S125_wifi_firmware_analysis() {
  module_log_init "${FUNCNAME[0]}"
  module_title "WiFi Firmware and Driver Analysis"
  pre_module_reporter "${FUNCNAME[0]}"

  local WIFI_DRIVERS_FOUND=0
  local WIFI_FIRMWARE_FOUND=0
  local ENGINEERING_MODE_FOUND=0
  local SECURITY_BYPASS_FOUND=0
  
  export WIFI_ANALYSIS_DIR="${LOG_PATH_MODULE}/wifi_analysis"
  mkdir -p "${WIFI_ANALYSIS_DIR}"

  print_output "[*] Searching for WiFi firmware and drivers..."
  
  # Search for WiFi firmware files
  wifi_firmware_search
  
  # Search for WiFi drivers
  wifi_driver_search
  
  # Analyze WiFi configurations
  wifi_config_analysis
  
  # Check for engineering mode capabilities
  wifi_engineering_mode_check
  
  # Analyze register access patterns
  wifi_register_analysis
  
  # Check for security bypasses
  wifi_security_bypass_check
  
  # Analyze DFS and regulatory controls
  wifi_regulatory_analysis
  
  # Check for TX power modifications
  wifi_tx_power_analysis
  
  # Generate comprehensive report
  wifi_generate_report

  write_log ""
  write_log "[*] Statistics:${WIFI_DRIVERS_FOUND}:${WIFI_FIRMWARE_FOUND}:${ENGINEERING_MODE_FOUND}:${SECURITY_BYPASS_FOUND}"
  module_end_log "${FUNCNAME[0]}" "${WIFI_DRIVERS_FOUND}"
}

wifi_firmware_search() {
  print_output "[*] Searching for WiFi firmware files..."
  
  local FIRMWARE_PATHS=(
    "lib/firmware"
    "lib/firmware/iwlwifi"
    "lib/firmware/ath10k"
    "lib/firmware/brcm"
    "lib/firmware/rtlwifi"
    "lib/firmware/mediatek"
  )
  
  for FW_PATH in "${FIRMWARE_PATHS[@]}"; do
    if [[ -d "${FIRMWARE_PATH}/${FW_PATH}" ]]; then
      print_output "[+] Found WiFi firmware directory: ${FW_PATH}"
      
      mapfile -t FW_FILES < <(find "${FIRMWARE_PATH}/${FW_PATH}" -type f 2>/dev/null)
      for FW_FILE in "${FW_FILES[@]}"; do
        local FW_NAME=$(basename "${FW_FILE}")
        local FW_SIZE=$(stat -c%s "${FW_FILE}" 2>/dev/null || echo "0")
        
        print_output "[+] WiFi Firmware: ${FW_NAME} (${FW_SIZE} bytes)"
        echo "${FW_FILE}" >> "${WIFI_ANALYSIS_DIR}/firmware_files.txt"
        
        # Analyze firmware binary
        analyze_wifi_firmware "${FW_FILE}"
        
        ((WIFI_FIRMWARE_FOUND++))
      done
    fi
  done
}

wifi_driver_search() {
  print_output "[*] Searching for WiFi drivers..."
  
  local DRIVER_PATTERNS=(
    "iwlwifi"
    "ath10k"
    "ath9k"
    "brcmfmac"
    "rtl8xxxu"
    "mt76"
    "cfg80211"
    "mac80211"
  )
  
  for DRIVER in "${DRIVER_PATTERNS[@]}"; do
    mapfile -t DRIVER_FILES < <(find "${FIRMWARE_PATH}" -name "*${DRIVER}*.ko" -o -name "*${DRIVER}*.ko.xz" 2>/dev/null)
    
    for DRIVER_FILE in "${DRIVER_FILES[@]}"; do
      print_output "[+] WiFi Driver: $(basename "${DRIVER_FILE}")"
      echo "${DRIVER_FILE}" >> "${WIFI_ANALYSIS_DIR}/driver_files.txt"
      
      # Analyze driver binary
      analyze_wifi_driver "${DRIVER_FILE}"
      
      ((WIFI_DRIVERS_FOUND++))
    done
  done
}

analyze_wifi_firmware() {
  local FW_FILE="${1}"
  local FW_NAME=$(basename "${FW_FILE}")
  local ANALYSIS_FILE="${WIFI_ANALYSIS_DIR}/firmware_${FW_NAME}.txt"
  
  {
    echo "=== WiFi Firmware Analysis: ${FW_NAME} ==="
    echo "File: ${FW_FILE}"
    echo "Size: $(stat -c%s "${FW_FILE}" 2>/dev/null || echo "0") bytes"
    echo ""
    
    # Check for engineering mode signatures
    echo "[*] Checking for engineering mode signatures..."
    if grep -q "engineering" "${FW_FILE}" 2>/dev/null; then
      echo "[!] FOUND: Engineering mode references"
      ((ENGINEERING_MODE_FOUND++))
    fi
    
    # Check for debug strings
    echo "[*] Checking for debug strings..."
    strings "${FW_FILE}" | grep -i "debug\|test\|eng\|dev" | head -20
    
    # Check for register access patterns
    echo "[*] Checking for register access patterns..."
    strings "${FW_FILE}" | grep -i "register\|mmio\|csr" | head -20
    
    # Check for security-related strings
    echo "[*] Checking for security strings..."
    strings "${FW_FILE}" | grep -i "auth\|crypt\|secure\|bypass" | head -20
    
  } > "${ANALYSIS_FILE}"
}

analyze_wifi_driver() {
  local DRIVER_FILE="${1}"
  local DRIVER_NAME=$(basename "${DRIVER_FILE}")
  local ANALYSIS_FILE="${WIFI_ANALYSIS_DIR}/driver_${DRIVER_NAME}.txt"
  
  # Decompress if needed
  local TEMP_DRIVER="${DRIVER_FILE}"
  if [[ "${DRIVER_FILE}" == *.xz ]]; then
    TEMP_DRIVER="/tmp/$(basename "${DRIVER_FILE}" .xz)"
    xz -dc "${DRIVER_FILE}" > "${TEMP_DRIVER}" 2>/dev/null
  fi
  
  {
    echo "=== WiFi Driver Analysis: ${DRIVER_NAME} ==="
    echo "File: ${DRIVER_FILE}"
    echo ""
    
    # Check for module parameters
    echo "[*] Checking for module parameters..."
    if command -v modinfo &>/dev/null && [[ -f "${TEMP_DRIVER}" ]]; then
      modinfo "${TEMP_DRIVER}" 2>/dev/null | grep "parm:" || echo "No parameters found"
    fi
    
    # Check for engineering mode functions
    echo "[*] Checking for engineering mode functions..."
    strings "${TEMP_DRIVER}" | grep -i "engineering\|debug_mode\|test_mode" | head -20
    
    # Check for register programming functions
    echo "[*] Checking for register programming..."
    strings "${TEMP_DRIVER}" | grep -i "write_reg\|read_reg\|mmio\|csr_write" | head -20
    
    # Check for security bypass indicators
    echo "[*] Checking for security bypass indicators..."
    strings "${TEMP_DRIVER}" | grep -i "bypass\|disable.*check\|skip.*verify" | head -20
    
    # Check for TX power controls
    echo "[*] Checking for TX power controls..."
    strings "${TEMP_DRIVER}" | grep -i "tx_power\|txpower\|power_level" | head -20
    
  } > "${ANALYSIS_FILE}"
  
  # Cleanup temp file
  [[ "${TEMP_DRIVER}" != "${DRIVER_FILE}" ]] && rm -f "${TEMP_DRIVER}"
}

wifi_config_analysis() {
  print_output "[*] Analyzing WiFi configurations..."
  
  local CONFIG_PATHS=(
    "etc/modprobe.d"
    "etc/modules-load.d"
    "etc/NetworkManager"
    "etc/wpa_supplicant"
  )
  
  for CONFIG_PATH in "${CONFIG_PATHS[@]}"; do
    if [[ -d "${FIRMWARE_PATH}/${CONFIG_PATH}" ]]; then
      mapfile -t CONFIG_FILES < <(find "${FIRMWARE_PATH}/${CONFIG_PATH}" -type f 2>/dev/null)
      
      for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
        if grep -qi "wifi\|wlan\|iwl\|ath\|brcm\|rtl" "${CONFIG_FILE}" 2>/dev/null; then
          print_output "[+] WiFi Config: $(basename "${CONFIG_FILE}")"
          cp "${CONFIG_FILE}" "${WIFI_ANALYSIS_DIR}/" 2>/dev/null
        fi
      done
    fi
  done
}

wifi_engineering_mode_check() {
  print_output "[*] Checking for engineering mode capabilities..."
  
  local ENG_PATTERNS=(
    "engineering_mode"
    "debug_mode"
    "test_mode"
    "dev_mode"
    "factory_mode"
  )
  
  for PATTERN in "${ENG_PATTERNS[@]}"; do
    if grep -r "${PATTERN}" "${FIRMWARE_PATH}" 2>/dev/null | head -5 >> "${WIFI_ANALYSIS_DIR}/engineering_mode.txt"; then
      print_output "[!] Found engineering mode pattern: ${PATTERN}"
      ((ENGINEERING_MODE_FOUND++))
    fi
  done
}

wifi_register_analysis() {
  print_output "[*] Analyzing register access patterns..."
  
  {
    echo "=== WiFi Register Access Analysis ==="
    echo ""
    
    # Search for register definitions
    echo "[*] Register definitions found:"
    grep -r "CSR_\|REG_\|MMIO_" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -30
    
    # Search for register access functions
    echo ""
    echo "[*] Register access functions:"
    grep -r "write_register\|read_register\|iowrite\|ioread" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -30
    
  } > "${WIFI_ANALYSIS_DIR}/register_access.txt"
}

wifi_security_bypass_check() {
  print_output "[*] Checking for security bypass mechanisms..."
  
  local BYPASS_PATTERNS=(
    "bypass.*check"
    "disable.*security"
    "skip.*verify"
    "no.*auth"
    "insecure"
  )
  
  {
    echo "=== WiFi Security Bypass Analysis ==="
    echo ""
    
    for PATTERN in "${BYPASS_PATTERNS[@]}"; do
      echo "[*] Checking pattern: ${PATTERN}"
      if grep -ri "${PATTERN}" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -10; then
        ((SECURITY_BYPASS_FOUND++))
      fi
      echo ""
    done
    
  } > "${WIFI_ANALYSIS_DIR}/security_bypass.txt"
}

wifi_regulatory_analysis() {
  print_output "[*] Analyzing regulatory and DFS controls..."
  
  {
    echo "=== WiFi Regulatory Analysis ==="
    echo ""
    
    # Check for regulatory database
    echo "[*] Regulatory database files:"
    find "${FIRMWARE_PATH}" -name "regulatory.db*" -o -name "*.pem" 2>/dev/null
    
    # Check for DFS controls
    echo ""
    echo "[*] DFS control mechanisms:"
    grep -ri "dfs\|radar" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -20
    
    # Check for country code controls
    echo ""
    echo "[*] Country code controls:"
    grep -ri "country.*code\|regdom" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -20
    
  } > "${WIFI_ANALYSIS_DIR}/regulatory_analysis.txt"
}

wifi_tx_power_analysis() {
  print_output "[*] Analyzing TX power controls..."
  
  {
    echo "=== WiFi TX Power Analysis ==="
    echo ""
    
    # Check for TX power limits
    echo "[*] TX power limit configurations:"
    grep -ri "tx.*power\|txpower\|power.*limit" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -30
    
    # Check for power table modifications
    echo ""
    echo "[*] Power table references:"
    grep -ri "power.*table\|tx.*table" "${FIRMWARE_PATH}" 2>/dev/null | grep -i "wifi\|wlan" | head -20
    
  } > "${WIFI_ANALYSIS_DIR}/tx_power_analysis.txt"
}

wifi_generate_report() {
  print_output "[*] Generating comprehensive WiFi analysis report..."
  
  {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          WiFi Firmware & Driver Analysis Report               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Analysis Date: $(date)"
    echo "Firmware Path: ${FIRMWARE_PATH}"
    echo ""
    echo "=== Summary Statistics ==="
    echo "WiFi Firmware Files Found: ${WIFI_FIRMWARE_FOUND}"
    echo "WiFi Driver Files Found: ${WIFI_DRIVERS_FOUND}"
    echo "Engineering Mode Indicators: ${ENGINEERING_MODE_FOUND}"
    echo "Security Bypass Indicators: ${SECURITY_BYPASS_FOUND}"
    echo ""
    echo "=== Detailed Analysis Files ==="
    echo "Analysis Directory: ${WIFI_ANALYSIS_DIR}"
    ls -lh "${WIFI_ANALYSIS_DIR}/" 2>/dev/null
    echo ""
    echo "=== Security Recommendations ==="
    
    if [[ ${ENGINEERING_MODE_FOUND} -gt 0 ]]; then
      echo "[!] WARNING: Engineering mode capabilities detected"
      echo "    - Review engineering mode access controls"
      echo "    - Ensure engineering mode is disabled in production"
      echo "    - Audit register access permissions"
    fi
    
    if [[ ${SECURITY_BYPASS_FOUND} -gt 0 ]]; then
      echo "[!] CRITICAL: Security bypass mechanisms detected"
      echo "    - Review all bypass mechanisms for legitimacy"
      echo "    - Ensure bypasses are properly protected"
      echo "    - Consider removing unnecessary bypass code"
    fi
    
    echo ""
    echo "=== Next Steps ==="
    echo "1. Review individual analysis files in ${WIFI_ANALYSIS_DIR}"
    echo "2. Examine firmware binaries for backdoors or vulnerabilities"
    echo "3. Audit driver code for security issues"
    echo "4. Test WiFi security controls in runtime environment"
    echo "5. Document all findings and remediation steps"
    
  } > "${WIFI_ANALYSIS_DIR}/WIFI_ANALYSIS_REPORT.txt"
  
  print_output "[+] Report generated: ${WIFI_ANALYSIS_DIR}/WIFI_ANALYSIS_REPORT.txt"
}
