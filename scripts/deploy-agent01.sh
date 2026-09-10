#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-pve01}"
CONFIG="$ROOT/proxmox/pve01/guests/agent01.yml"

MONITOR_CT_ID="${MONITOR_CT_ID:-100}"
TRACE_IP="${TRACE_IP:-192.168.10.20}"
TRACE_OTLP_PORT="${TRACE_OTLP_PORT:-4317}"

CREATED=0
DEPLOY_OK=0

remote() {
    local cmd
    printf -v cmd '%q ' "$@"
    printf '%s\n' "$cmd" | ssh -T "$PVE_HOST" 'bash -se'
}

rollback() {
    local rc=$?

    if [[ "$DEPLOY_OK" -eq 0 && "$CREATED" -eq 1 ]]; then
        echo
        echo "[ROLLBACK] agent01 provisioning failed."
        echo "[ROLLBACK] Removing newly-created VMID $VMID only."

        remote pct stop "$VMID" >/dev/null 2>&1 || true
        remote pct destroy "$VMID" >/dev/null 2>&1 || true

        echo "[ROLLBACK] Newly-created agent01 removed."
    fi

    exit "$rc"
}

trap rollback EXIT

[[ -f "$CONFIG" ]] || {
    echo "[ERROR] Missing $CONFIG"
    exit 1
}

read -r \
    VMID \
    NAME \
    TEMPLATE \
    OSTYPE \
    CORES \
    MEMORY \
    SWAP \
    STORAGE \
    DISK_SIZE \
    IFACE \
    BRIDGE \
    IPV4 \
    GATEWAY \
    UNPRIVILEGED \
    ONBOOT \
    ORDER \
    UP_DELAY \
    DOWN_TIMEOUT < <(
    python3 - "$CONFIG" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1]))

print(
    data["vmid"],
    data["name"],
    data["os"]["template"],
    data["os"]["ostype"],
    data["resources"]["cores"],
    data["resources"]["memory_mib"],
    data["resources"]["swap_mib"],
    data["resources"]["rootfs"]["storage"],
    data["resources"]["rootfs"]["size_gib"],
    data["network"]["interface"],
    data["network"]["bridge"],
    data["network"]["ipv4"],
    data["network"]["gateway4"],
    1 if data["security"]["unprivileged"] else 0,
    1 if data["boot"]["onboot"] else 0,
    data["boot"]["order"],
    data["boot"]["startup_delay_seconds"],
    data["boot"]["shutdown_timeout_seconds"],
)
PY
)

IP_ADDR="${IPV4%%/*}"

echo "========================================"
echo " agent01 provisioning"
echo "========================================"
echo "PVE host : $PVE_HOST"
echo "VMID     : $VMID"
echo "Hostname : $NAME"
echo "IPv4     : $IPV4"
echo "Template : $TEMPLATE"
echo

echo "==> Preflight: pve01"
remote true >/dev/null
echo "[OK] pve01 reachable"

echo "==> Preflight: template"
remote pveam list local |
    grep -Fq "$TEMPLATE"
echo "[OK] template available"

echo "==> Preflight: storage"
remote pvesm status |
    awk -v storage="$STORAGE" '
        $1 == storage && $3 == "active" { found=1 }
        END { exit !found }
    '
echo "[OK] $STORAGE active"

echo "==> Preflight: VMID"

if remote pct status "$VMID" >/dev/null 2>&1; then
    ACTUAL_NAME="$(
        remote pct config "$VMID" |
            awk '$1 == "hostname:" { print $2 }'
    )"

    if [[ "$ACTUAL_NAME" != "$NAME" ]]; then
        echo "[ERROR] VMID $VMID already belongs to '$ACTUAL_NAME'"
        exit 1
    fi

    echo "[OK] Existing VMID $VMID belongs to $NAME"
else
    NEXTID="$(remote pvesh get /cluster/nextid)"

    if [[ "$NEXTID" != "$VMID" ]]; then
        echo "[ERROR] VMID $VMID is not the current next free ID ($NEXTID)"
        exit 1
    fi

    echo "[OK] VMID $VMID available"

    echo "==> Preflight: IPv4 address"

    remote ip neigh del "$IP_ADDR" dev "$BRIDGE" >/dev/null 2>&1 || true
    remote ping -c 2 -W 1 "$IP_ADDR" >/dev/null 2>&1 || true

    NEIGH="$(
        remote ip neigh show "$IP_ADDR" dev "$BRIDGE" || true
)"

    NEIGH_STATE="$(
        awk 'NF { print $NF; exit }' <<< "$NEIGH"
)"

    case "$NEIGH_STATE" in
        ""|FAILED|INCOMPLETE)
            echo "[OK] no conflicting neighbor observed for $IP_ADDR"
            ;;
        *)
            echo "[ERROR] IPv4 address $IP_ADDR appears to be in use:"
            echo "$NEIGH"
            exit 1
            ;;
    esac

if ! remote pct status "$VMID" >/dev/null 2>&1; then
    echo
    echo "==> Creating agent01"

    remote pct create "$VMID" "$TEMPLATE" \
        --hostname "$NAME" \
        --ostype "$OSTYPE" \
        --arch amd64 \
        --cores "$CORES" \
        --memory "$MEMORY" \
        --swap "$SWAP" \
        --rootfs "${STORAGE}:${DISK_SIZE}" \
        --net0 "name=${IFACE},bridge=${BRIDGE},ip=${IPV4},gw=${GATEWAY},type=veth" \
        --unprivileged "$UNPRIVILEGED" \
        --onboot "$ONBOOT" \
        --startup "order=${ORDER},up=${UP_DELAY},down=${DOWN_TIMEOUT}"

    CREATED=1
    echo "[OK] agent01 created"
else
    echo
    echo "==> Reconciling existing agent01"

    remote pct set "$VMID" \
        --cores "$CORES" \
        --memory "$MEMORY" \
        --swap "$SWAP" \
        --net0 "name=${IFACE},bridge=${BRIDGE},ip=${IPV4},gw=${GATEWAY},type=veth" \
        --onboot "$ONBOOT" \
        --startup "order=${ORDER},up=${UP_DELAY},down=${DOWN_TIMEOUT}"

    echo "[OK] mutable configuration synchronized"
fi

echo
echo "==> Starting agent01"

STATUS="$(remote pct status "$VMID")"

if ! grep -q 'status: running' <<< "$STATUS"; then
    remote pct start "$VMID"
fi

for _ in $(seq 1 30); do
    if remote pct exec "$VMID" -- true >/dev/null 2>&1; then
        break
    fi

    sleep 1
done

remote pct exec "$VMID" -- true >/dev/null
echo "[OK] container running"

echo
echo "==> Verifying operating system"

remote pct exec "$VMID" -- \
    bash -lc "grep -q '^VERSION_ID=\"13\"$' /etc/os-release"

echo "[OK] Debian 13"

echo
echo "==> Verifying network configuration"

remote pct exec "$VMID" -- \
    bash -lc "ip -4 addr show dev '$IFACE' | grep -F '$IPV4'"

remote pct exec "$VMID" -- \
    bash -lc "ip route | grep -F 'default via $GATEWAY'"

echo "[OK] IP and default route"

echo
echo "==> Verifying gateway and DNS"

remote pct exec "$VMID" -- \
    ping -c 2 -W 1 "$GATEWAY" >/dev/null

remote pct exec "$VMID" -- \
    bash -lc "getent hosts deb.debian.org >/dev/null"

echo "[OK] gateway and DNS"

echo
echo "==> Verifying Tempo OTLP reachability"

remote pct exec "$VMID" -- \
    bash -lc "timeout 3 bash -c '</dev/tcp/${TRACE_IP}/${TRACE_OTLP_PORT}'"

echo "[OK] Tempo OTLP ${TRACE_IP}:${TRACE_OTLP_PORT} reachable"

echo
echo "==> Verifying monitoring path to agent01"

remote pct exec "$MONITOR_CT_ID" -- \
    ping -c 2 -W 1 "$IP_ADDR" >/dev/null

echo "[OK] mon01 can reach $IP_ADDR"

echo
echo "==> Runtime configuration"

remote pct config "$VMID"

echo
echo "==> Existing monitoring regression check"

"$ROOT/scripts/verify-monitoring.sh"

echo
echo "========================================"
echo " agent01 provisioning successful ✅"
echo " Phase 1 network preflight passed ✅"
echo " Existing monitoring remains healthy ✅"
echo "========================================"

DEPLOY_OK=1
