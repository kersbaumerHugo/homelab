#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-root@pve01}"
GUEST="${1:-mon01}"
case "$GUEST" in
    mon01) GUEST_TYPE="pct" ;;
    ha01)  GUEST_TYPE="qm" ;;
    *) echo "[ERROR] Unsupported guest: $GUEST" >&2; exit 1 ;;
esac
CONFIG="$ROOT/proxmox/pve01/guests/${GUEST}.yml"

remote() {
    local cmd

    printf -v cmd '%q ' "$@"

    printf '%s\n' "$cmd" |
        ssh -T "$PVE_HOST" 'bash -se'
}


[[ -f "$CONFIG" ]] || {
    echo "[ERROR] Missing $CONFIG"
    exit 1
}

read -r VMID ONBOOT ORDER UP DOWN < <(
    python3 - "$CONFIG" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1]))

boot = data["boot"]

print(
    data["vmid"],
    1 if boot["onboot"] else 0,
    boot["order"],
    boot["startup_delay_seconds"],
    boot["shutdown_timeout_seconds"],
)
PY
)

echo "==> Deploying guest boot policy"

remote "$GUEST_TYPE" status "$VMID" >/dev/null

remote \
  "$GUEST_TYPE" set "$VMID" \
  --onboot "$ONBOOT" \
  --startup "order=$ORDER,up=$UP,down=$DOWN"

echo "==> Verifying"

ACTUAL="$(
    remote "$GUEST_TYPE" config "$VMID" \
      | grep -E '^(onboot|startup):'
)"

printf '%s\n' "$ACTUAL"

grep -q '^onboot: 1$' <<< "$ACTUAL"
grep -q "order=$ORDER" <<< "$ACTUAL"
grep -q "up=$UP" <<< "$ACTUAL"
grep -q "down=$DOWN" <<< "$ACTUAL"

echo "Guest boot policy deployment successful ✅"
