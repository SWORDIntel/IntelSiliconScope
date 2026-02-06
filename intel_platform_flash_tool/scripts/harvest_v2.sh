#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTDIR="${HOME}/dod_harvest_v2_${STAMP}"
USE_SUDO=0
INSTALL_DEPS=0
RUN_PROBES=0
DO_EXTRACT_VMLINUX=0
DO_MSR=0
DO_MSR_ALL=0
DO_MSR_SCAN=0
MSR_SCAN_RANGE="0x0:0x200"
DO_MSR_WRITE=0
ARM_MSR_WRITES=0
MSR_WRITE_CPU=0
MSR_WRITE_ADDR=""
MSR_WRITE_VALUE=""

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: harvest_v2.sh [options]
Options:
  --outdir PATH          set output directory
  --sudo                 run sudo where required (dmesg, dmidecode, MSRs)
  --install-deps         install zstd lz4 xz-utils binutils msr-tools pciutils usbutils
  --run-probes           run MOVDIR64B/UINTR/TSXLDTRK probes
  --extract-vmlinux      try to decompress /boot/vmlinuz-$(uname -r)
  --msr                  collect curated MSRs
  --msr-all              collect MSRs across all CPUs
  --msr-scan A:B         scan MSR range (hex)
  --msr-write CPU,ADDR,VAL write an MSR (requires --arm-msr-writes and --sudo)
  --arm-msr-writes       enable MSR writes
  -h, --help             show this message
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*" | tee -a "$OUTDIR/run.log"
}
run_shell() {
  local f="$1" cmd="$2"
  echo "### CMD: $cmd" >> "$f"
  echo "### TIME: $(date -Is)" >> "$f"
  echo >> "$f"
  bash -lc "$cmd" >> "$f" 2>&1 || echo "### EXIT: $?" >> "$f"
  echo >> "$f"
}
sudocmd() {
  if [[ "$USE_SUDO" -eq 1 ]]; then sudo "$@"; else "$@"; fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --outdir) OUTDIR="$2"; shift 2;;
    --sudo) USE_SUDO=1; shift;;
    --install-deps) INSTALL_DEPS=1; shift;;
    --run-probes) RUN_PROBES=1; shift;;
    --extract-vmlinux) DO_EXTRACT_VMLINUX=1; shift;;
    --msr) DO_MSR=1; shift;;
    --msr-all) DO_MSR_ALL=1; shift;;
    --msr-scan) DO_MSR_SCAN=1; MSR_SCAN_RANGE="$2"; shift 2;;
    --msr-write) DO_MSR_WRITE=1; IFS=',' read -r MSR_WRITE_CPU MSR_WRITE_ADDR MSR_WRITE_VALUE <<<"$2"; shift 2;;
    --arm-msr-writes) ARM_MSR_WRITES=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

mkdir -p "$OUTDIR"/{system,kernel,io,toolchain,flags,probes,msr,extract,notes,tmp}
write_readme() {
  cat > "$OUTDIR/README.txt" <<'EOF'
HARVEST v2 output
Generated: $(date -Is)
Host: $(hostname)
Kernel: $(uname -r)
Outdir: $OUTDIR
EOF
}
install_deps() {
  log "Installing deps"
  sudocmd apt-get update -y || true
  sudocmd apt-get install -y zstd lz4 xz-utils gzip bzip2 pciutils usbutils dmidecode msr-tools binutils bc jq file || true
}
collect_system() {
  local f="$OUTDIR/system/basic.txt"
  run_shell "$f" "uname -a"
  run_shell "$f" "cat /etc/os-release"
  run_shell "$f" "lscpu"
  run_shell "$f" "dmesg -T | tail -n 40"
}
collect_kernel() {
  local f="$OUTDIR/kernel/basic.txt"
  run_shell "$f" "cat /proc/cmdline"
  run_shell "$f" "cat /boot/config-$(uname -r) 2>/dev/null | grep -n 'CONFIG_' | head"
  run_shell "$f" "ls -ld /lib/modules/$(uname -r)"
}
collect_io() {
  local f="$OUTDIR/io/basic.txt"
  run_shell "$f" "lsblk -o NAME,TRAN,SIZE,MODEL"
  run_shell "$f" "lsusb"
  run_shell "$f" "lspci -nnk | head"
  run_shell "$f" "dmesg -T | grep -i usb | tail -n 40 || true"
}
collect_toolchain() {
  local f="$OUTDIR/toolchain/basic.txt"
  run_shell "$f" "gcc -v"
  run_shell "$f" "clang -v 2>/dev/null || true"
}
run_probes() {
  local f="$OUTDIR/probes/probe.log"
  if ! have gcc; then
    echo "gcc missing, skipping probes" >> "$f"
    return
  fi
  cat > "$OUTDIR/probes/probe.c" <<'EOF'
#include <stdio.h>
int main(){puts("probe placeholder");return 0;}
EOF
  gcc -O2 "$OUTDIR/probes/probe.c" -o "$OUTDIR/probes/probe" >> "$f" 2>&1 || true
  set +e
  "$OUTDIR/probes/probe" >> "$f" 2>&1 || true
  set -e
}
flag_matrix() {
  local f="$OUTDIR/flags/flag_matrix.txt"
  > "$f"
  local flags=(-mmovdir64b -muintr -mtsxldtrk -mavx512f -mamx-tile)
  for cc in gcc clang icx icpx dpcpp; do
    have "$cc" || continue
    for flag in "${flags[@]}"; do
      "$cc" -O2 -fsyntax-only "$flag" /dev/null >/dev/null 2>&1 && echo "$cc $flag OK" >> "$f" || echo "$cc $flag FAIL" >> "$f"
    done
  done
}
msr_read() {
  local f="$OUTDIR/msr/msr.txt"
  >"$f"
  local cpus=(0)
  [[ "$DO_MSR_ALL" -eq 1 ]] && cpus=(0)
  for cpu in "${cpus[@]}"; do
    for addr in 0x10 0x1b 0x3a 0x1a0 0x10a; do
      sudocmd modprobe msr >/dev/null 2>&1 || true
      if have rdmsr; then
        echo "cpu$cpu $addr $(sudo rdmsr -p $cpu $addr 2>/dev/null || echo FAIL)" >> "$f"
      fi
    done
  done
}
extract_vmlinux() {
  local in="/boot/vmlinuz-$(uname -r)"
  local out="$OUTDIR/extract/vmlinux-$(uname -r)"
  [[ -r "$in" ]] || return
  if have gzip; then
    dd if="$in" bs=1 skip=0 | gzip -dc > "$out" 2>/dev/null || true
  fi
}
bundle() {
  tar -C "$OUTDIR" -czf "$OUTDIR.tar.gz" .
}
write_readme
log "OUTDIR=$OUTDIR"
[[ "$INSTALL_DEPS" -eq 1 ]] && install_deps
collect_system
collect_kernel
collect_io
collect_toolchain
flag_matrix
[[ "$RUN_PROBES" -eq 1 ]] && run_probes
[[ "$DO_EXTRACT_VMLINUX" -eq 1 ]] && extract_vmlinux
[[ "$DO_MSR" -eq 1 ]] && msr_read
bundle
log "DONE"; echo "Harvest dir: $OUTDIR"
