#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-pve01}"
CONFIG="$ROOT/proxmox/pve01/guests/agent01.yml"

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
        echo "[ROLLBACK] agent01 deployment failed."
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
    VMID NAME TEMPLATE OSTYPE CORES MEMORY SWAP STORAGE DISK_SIZE \
    IFACE BRIDGE IPV4 GATEWAY UNPRIVILEGED NESTING KEYCTL \
    ONBOOT ORDER UP_DELAY DOWN_TIMEOUT < <(
    python3 - "$CONFIG" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))

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
    1 if data["security"]["nesting"] else 0,
    1 if data["security"]["keyctl"] else 0,
    1 if data["boot"]["onboot"] else 0,
    data["boot"]["order"],
    data["boot"]["startup_delay_seconds"],
    data["boot"]["shutdown_timeout_seconds"],
)
PY
)

FEATURES="nesting=${NESTING},keyctl=${KEYCTL}"
EXPECTED_ROOTFS_SIZE="size=${DISK_SIZE}G"

echo "========================================"
echo " agent01 deployment"
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
remote pveam list local | grep -Fq "$TEMPLATE"
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
fi

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
        --features "$FEATURES" \
        --onboot "$ONBOOT" \
        --startup "order=${ORDER},up=${UP_DELAY},down=${DOWN_TIMEOUT}"

    CREATED=1
    echo "[OK] agent01 created"
else
    echo
    echo "==> Validating safety-sensitive configuration"

    ACTUAL_UNPRIVILEGED="$(
        remote pct config "$VMID" |
            awk '$1 == "unprivileged:" { print $2 }'
    )"

    if [[ "$ACTUAL_UNPRIVILEGED" != "$UNPRIVILEGED" ]]; then
        echo "[ERROR] unprivileged drift: expected $UNPRIVILEGED, got ${ACTUAL_UNPRIVILEGED:-missing}"
        exit 1
    fi

    ACTUAL_ROOTFS="$(
        remote pct config "$VMID" |
            sed -n 's/^rootfs: //p'
    )"

    if [[ "$ACTUAL_ROOTFS" != "${STORAGE}:"* ]]; then
        echo "[ERROR] rootfs storage drift: expected $STORAGE"
        echo "[ERROR] actual rootfs: $ACTUAL_ROOTFS"
        exit 1
    fi

    if [[ "$ACTUAL_ROOTFS" != *"$EXPECTED_ROOTFS_SIZE"* ]]; then
        echo "[ERROR] rootfs size drift: expected ${DISK_SIZE}G"
        echo "[ERROR] actual rootfs: $ACTUAL_ROOTFS"
        echo "[ERROR] disk resize is intentionally not automatic."
        exit 1
    fi

    echo "[OK] unprivileged/rootfs safety checks"

    echo
    echo "==> Reconciling mutable agent01 configuration"

    remote pct set "$VMID" \
        --cores "$CORES" \
        --memory "$MEMORY" \
        --swap "$SWAP" \
        --features "$FEATURES" \
        --onboot "$ONBOOT" \
        --startup "order=${ORDER},up=${UP_DELAY},down=${DOWN_TIMEOUT}"

    CURRENT_NET="$(
        remote pct config "$VMID" |
            sed -n 's/^net0: //p'
    )"

    NET_DRIFT=0

    for token in \
        "name=${IFACE}" \
        "bridge=${BRIDGE}" \
        "ip=${IPV4}" \
        "gw=${GATEWAY}" \
        "type=veth"
    do
        if [[ ",$CURRENT_NET," != *",$token,"* ]]; then
            NET_DRIFT=1
        fi
    done

    if [[ "$NET_DRIFT" -eq 1 ]]; then
        remote pct set "$VMID" \
            --net0 "name=${IFACE},bridge=${BRIDGE},ip=${IPV4},gw=${GATEWAY},type=veth"
        echo "[OK] network configuration reconciled"
    else
        echo "[OK] network configuration already synchronized"
    fi

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
echo "==> Verifying security features"

ACTUAL_FEATURES="$(
    remote pct config "$VMID" |
        sed -n 's/^features: //p'
)"

grep -Eq '(^|,)nesting=1(,|$)' <<< "$ACTUAL_FEATURES"
grep -Eq '(^|,)keyctl=1(,|$)' <<< "$ACTUAL_FEATURES"

echo "[OK] nesting=1"
echo "[OK] keyctl=1"

echo
echo "==> Verifying network configuration"

remote pct exec "$VMID" -- \
    bash -lc "ip -4 addr show dev '$IFACE' | grep -F '$IPV4'"

remote pct exec "$VMID" -- \
    bash -lc "ip route | grep -F 'default via $GATEWAY'"

echo "[OK] IP and default route"

echo
echo "==> Verifying DNS"

remote pct exec "$VMID" -- \
    bash -lc "getent hosts deb.debian.org >/dev/null"

echo "[OK] DNS resolution"

echo
echo "==> Runtime configuration"
remote pct config "$VMID"

DEPLOY_OK=1

echo
echo "========================================"
echo " agent01 guest deployment successful ✅"
echo "========================================"
