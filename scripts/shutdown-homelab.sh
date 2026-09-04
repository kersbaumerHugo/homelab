#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
PVE_IP="${PVE_IP:-192.168.10.10}"

info() {
    printf '\033[1;34m==>\033[0m %s\n' "$*"
}

ok() {
    printf '\033[0;32m[OK]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$*"
}

echo
echo "===================================="
echo "     Homelab graceful shutdown"
echo "===================================="
echo

info "Checking pve01 connectivity"

if ! ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    "$PVE_HOST" true 2>/dev/null
then
    warn "pve01 is already unreachable/offline"
    exit 0
fi

ok "pve01 reachable"

echo
info "Current guests"

ssh "$PVE_HOST" '
echo "--- LXC ---"
pct list

echo
echo "--- VMs ---"
qm list
'

echo
info "Checking Proxmox guest shutdown orchestration"

if ssh "$PVE_HOST" \
    'systemctl is-enabled --quiet pve-guests.service'
then
    ok "pve-guests.service enabled"
else
    warn "pve-guests.service is not enabled"
    exit 1
fi

echo
read -r -p "Power off the homelab? [y/N] " answer

case "$answer" in
    y|Y|yes|YES)
        ;;
    *)
        echo "Shutdown cancelled."
        exit 0
        ;;
esac

echo
info "Requesting graceful Proxmox shutdown"

# SSH may disconnect while systemd is shutting the host down.
ssh "$PVE_HOST" 'systemctl poweroff' 2>/dev/null || true

info "Waiting for pve01 to go offline"

for _ in {1..60}; do
    if ! ping -c 1 -W 1 "$PVE_IP" >/dev/null 2>&1; then
        echo
        ok "pve01 is offline"
        echo
        echo "Homelab shutdown completed ✅"
        exit 0
    fi

    printf "."
    sleep 2
done

echo
warn "pve01 did not become unreachable within 120 seconds"
warn "Check the machine physically before cutting power."
exit 1
