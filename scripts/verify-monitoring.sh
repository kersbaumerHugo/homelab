#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
CT_ID="${CT_ID:-100}"

ok() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$1"
}

fail() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2
    exit 1
}

remote() {
    ssh "$PVE_HOST" "pct exec $CT_ID -- bash -lc $(printf '%q' "$1")"
}

echo "=== Homelab monitoring verification ==="

ssh -o BatchMode=yes "$PVE_HOST" true \
    || fail "Cannot reach $PVE_HOST"
ok "pve01 reachable via SSH"

ssh "$PVE_HOST" "pct status $CT_ID" | grep -q "running" \
    || fail "mon01 is not running"
ok "mon01 running"

[[ "$(remote 'systemctl is-active prometheus')" == "active" ]] \
    || fail "Prometheus inactive"
ok "Prometheus active"

[[ "$(remote 'systemctl is-active grafana-server')" == "active" ]] \
    || fail "Grafana inactive"
ok "Grafana active"

remote "curl --fail --silent http://127.0.0.1:9090/-/healthy" >/dev/null \
    || fail "Prometheus health endpoint failed"
ok "Prometheus healthy"

remote "curl --fail --silent http://127.0.0.1:3000/api/health" >/dev/null \
    || fail "Grafana health endpoint failed"
ok "Grafana healthy"

TARGET="$(remote \
    "promtool query instant http://127.0.0.1:9090 'up{job=\"pve01\"}'" \
    2>/dev/null || true)"

grep -q '=> 1' <<< "$TARGET" \
    || fail "pve01 metrics target DOWN"
ok "pve01 metrics target UP"

TEMP="$(remote \
    "promtool query instant http://127.0.0.1:9090 \
    'max(node_hwmon_temp_celsius{instance=\"192.168.10.10:9100\",chip=\"platform_coretemp_0\"})'" \
    2>/dev/null || true)"

[[ -n "$TEMP" ]] || fail "CPU temperature metric missing"
ok "CPU temperature metric available"

FAILED_UNITS="$(
    ssh "$PVE_HOST" \
        "systemctl show --property=NFailedUnits --value"
)"

if ! [[ "$FAILED_UNITS" =~ ^[0-9]+$ ]]; then
    fail "Could not determine pve01 failed systemd unit count"
fi

if (( FAILED_UNITS > 0 )); then
    ssh "$PVE_HOST" "systemctl --failed --no-pager" || true
    fail "pve01 has $FAILED_UNITS failed systemd unit(s)"
fi

ok "pve01 has no failed systemd units"

ssh "$PVE_HOST" "pvesm status" | grep -q '^hdd-backup.*active' \
    || fail "hdd-backup unavailable"
ok "hdd-backup active"

echo
echo "========================================"
echo " Homelab monitoring verification OK ✅"
echo "========================================"
