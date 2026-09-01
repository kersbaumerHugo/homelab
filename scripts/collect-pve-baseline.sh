#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${1:-pve01}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$BASE_DIR/proxmox/pve01"
LXC_OUT="$BASE_DIR/proxmox/lxc/mon01"

mkdir -p "$OUT" "$LXC_OUT"

echo "Collecting pve01 baseline from $PVE_HOST..."

ssh "$PVE_HOST" 'hostname' > "$OUT/hostname.txt"
ssh "$PVE_HOST" 'pveversion -v' > "$OUT/pveversion.txt"
ssh "$PVE_HOST" 'uname -a' > "$OUT/kernel.txt"

ssh "$PVE_HOST" 'ip -br addr; echo; ip route' \
  > "$OUT/network-state.txt"

ssh "$PVE_HOST" 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL' \
  > "$OUT/block-devices.txt"

ssh "$PVE_HOST" 'pvs; echo; vgs; echo; lvs' \
  > "$OUT/lvm.txt"

ssh "$PVE_HOST" 'df -hT' \
  > "$OUT/filesystems.txt"

ssh "$PVE_HOST" 'cat /etc/network/interfaces' \
  > "$OUT/interfaces"

ssh "$PVE_HOST" 'cat /etc/fstab' \
  > "$OUT/fstab"

ssh "$PVE_HOST" 'cat /etc/default/grub' \
  > "$OUT/grub"

ssh "$PVE_HOST" 'cat /etc/pve/storage.cfg' \
  > "$OUT/storage.cfg"

ssh "$PVE_HOST" 'pct config 100' \
  > "$LXC_OUT/100.conf"

ssh "$PVE_HOST" 'systemctl --failed --no-legend || true' \
  > "$OUT/systemd-failed.txt"

ssh "$PVE_HOST" \
  "smartctl -H /dev/sda; smartctl -A /dev/sda | grep -Ei 'Reallocated|Pending|Uncorrect|CRC|Temperature|Power_On'" \
  > "$OUT/smart-sda.txt"

ssh "$PVE_HOST" \
  "smartctl -H /dev/sdb; smartctl -A /dev/sdb | grep -Ei 'Reallocated|Pending|Uncorrect|CRC|Temperature|Wear|Life|Power_On'" \
  > "$OUT/smart-sdb.txt"

ssh "$PVE_HOST" 'cat /etc/default/grub.d/installer.cfg' \
  > "$OUT/grub-installer.cfg"

ssh "$PVE_HOST" "dpkg-query -W -f='\${binary:Package}\t\${Version}\n' | sort" \
  > "$OUT/packages.txt"

ssh "$PVE_HOST" \
  'systemctl is-enabled smartmontools prometheus-node-exporter; systemctl is-active smartmontools prometheus-node-exporter' \
  > "$OUT/telemetry-services.txt"

ssh "$PVE_HOST" 'pct exec 100 -- cat /etc/prometheus/prometheus.yml' \
  > "$BASE_DIR/monitoring/prometheus/prometheus.yml"

ssh "$PVE_HOST" 'pct exec 100 -- systemctl cat prometheus' \
  > "$BASE_DIR/monitoring/prometheus/prometheus.service.txt"

echo "Baseline collected successfully."
