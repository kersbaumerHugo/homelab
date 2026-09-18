#!/usr/bin/env bash
set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-pve01}"
CONFIG="$ROOT/proxmox/pve01/guests/agent01.yml"

ERRORS=0

ok() {
    printf '[OK] %s\n' "$1"
}

bad() {
    printf '[ERROR] %s\n' "$1"
    ERRORS=$((ERRORS + 1))
}

section() {
    printf '\n=== %s ===\n' "$1"
}

remote() {
    local cmd
    printf -v cmd '%q ' "$@"
    printf '%s\n' "$cmd" | ssh -T "$PVE_HOST" 'bash -se'
}

ct() {
    remote pct exec "$VMID" -- "$@"
}

[[ -f "$CONFIG" ]] || {
    echo "[ERROR] Missing $CONFIG"
    exit 1
}

read -r \
    VMID NAME CORES MEMORY SWAP STORAGE DISK_SIZE \
    IFACE BRIDGE IPV4 GATEWAY UNPRIVILEGED NESTING KEYCTL \
    ONBOOT ORDER UP_DELAY DOWN_TIMEOUT DOCKER_VERSION < <(
    python3 - "$CONFIG" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))

print(
    data["vmid"],
    data["name"],
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
    data["runtime"]["docker_engine_version"],
)
PY
)

section "Connectivity"

if remote true >/dev/null 2>&1; then
    ok "pve01 reachable"
else
    bad "pve01 unreachable"
fi

STATUS="$(
    remote pct status "$VMID" 2>/dev/null || true
)"

if grep -q 'status: running' <<< "$STATUS"; then
    ok "agent01 running"
else
    bad "agent01 not running"
fi

section "Proxmox desired state"

PCT_CONFIG="$(
    remote pct config "$VMID" 2>/dev/null || true
)"

check_scalar() {
    local key="$1"
    local expected="$2"
    local actual

    actual="$(
        awk -v key="${key}:" '$1 == key { print $2 }' <<< "$PCT_CONFIG"
    )"

    if [[ "$actual" == "$expected" ]]; then
        ok "$key=$expected"
    else
        bad "$key expected '$expected', got '${actual:-missing}'"
    fi
}

check_scalar hostname "$NAME"
check_scalar cores "$CORES"
check_scalar memory "$MEMORY"
check_scalar swap "$SWAP"
check_scalar unprivileged "$UNPRIVILEGED"
check_scalar onboot "$ONBOOT"

FEATURES="$(
    sed -n 's/^features: //p' <<< "$PCT_CONFIG"
)"

if grep -Eq "(^|,)nesting=${NESTING}(,|$)" <<< "$FEATURES"; then
    ok "nesting=$NESTING"
else
    bad "nesting=$NESTING missing"
fi

if grep -Eq "(^|,)keyctl=${KEYCTL}(,|$)" <<< "$FEATURES"; then
    ok "keyctl=$KEYCTL"
else
    bad "keyctl=$KEYCTL missing"
fi

ROOTFS="$(
    sed -n 's/^rootfs: //p' <<< "$PCT_CONFIG"
)"

if [[ "$ROOTFS" == "${STORAGE}:"* ]]; then
    ok "rootfs storage=$STORAGE"
else
    bad "rootfs storage drift: $ROOTFS"
fi

if [[ "$ROOTFS" == *"size=${DISK_SIZE}G"* ]]; then
    ok "rootfs size=${DISK_SIZE}G"
else
    bad "rootfs size drift: $ROOTFS"
fi

NET0="$(
    sed -n 's/^net0: //p' <<< "$PCT_CONFIG"
)"

for token in \
    "name=${IFACE}" \
    "bridge=${BRIDGE}" \
    "ip=${IPV4}" \
    "gw=${GATEWAY}" \
    "type=veth"
do
    if [[ ",$NET0," == *",$token,"* ]]; then
        ok "net0 contains $token"
    else
        bad "net0 missing $token"
    fi
done

STARTUP="$(
    sed -n 's/^startup: //p' <<< "$PCT_CONFIG"
)"

for token in \
    "order=${ORDER}" \
    "up=${UP_DELAY}" \
    "down=${DOWN_TIMEOUT}"
do
    if [[ ",$STARTUP," == *",$token,"* ]]; then
        ok "startup contains $token"
    else
        bad "startup missing $token"
    fi
done

section "Guest operating system"

if ct bash -lc "grep -q '^VERSION_ID=\"13\"$' /etc/os-release" \
    >/dev/null 2>&1
then
    ok "Debian 13"
else
    bad "unexpected guest operating system"
fi

section "Docker runtime"

if ct systemctl is-active --quiet docker.service >/dev/null 2>&1; then
    ok "docker.service active"
else
    bad "docker.service inactive"
fi

if ct systemctl is-enabled --quiet docker.service >/dev/null 2>&1; then
    ok "docker.service enabled"
else
    bad "docker.service disabled"
fi

ACTUAL_DOCKER_VERSION="$(
    ct docker version --format '{{.Server.Version}}' 2>/dev/null || true
)"

if [[ "$ACTUAL_DOCKER_VERSION" == "$DOCKER_VERSION" ]]; then
    ok "Docker Engine $DOCKER_VERSION"
else
    bad "Docker version expected '$DOCKER_VERSION', got '${ACTUAL_DOCKER_VERSION:-missing}'"
fi

DOCKER_INFO="$(
    ct docker info --format \
        '{{.Driver}}|{{.CgroupDriver}}|{{.CgroupVersion}}|{{json .SecurityOptions}}' \
        2>/dev/null || true
)"

IFS='|' read -r \
    STORAGE_DRIVER \
    CGROUP_DRIVER \
    CGROUP_VERSION \
    SECURITY_OPTIONS <<< "$DOCKER_INFO"

if [[ "$STORAGE_DRIVER" == "overlayfs" ]]; then
    ok "Docker storage driver overlayfs"
else
    bad "Docker storage driver expected overlayfs, got '${STORAGE_DRIVER:-missing}'"
fi

if [[ "$CGROUP_DRIVER" == "systemd" ]]; then
    ok "Docker cgroup driver systemd"
else
    bad "Docker cgroup driver expected systemd, got '${CGROUP_DRIVER:-missing}'"
fi

if [[ "$CGROUP_VERSION" == "2" ]]; then
    ok "Docker cgroup v2"
else
    bad "Docker cgroup version expected 2, got '${CGROUP_VERSION:-missing}'"
fi

if grep -q 'seccomp' <<< "$SECURITY_OPTIONS"; then
    ok "Docker seccomp available"
else
    bad "Docker seccomp unavailable"
fi

section "Hardened container capability smoke"

if ct docker image inspect hello-world:latest >/dev/null 2>&1; then
    if ct docker run --rm \
        --pull=never \
        --network none \
        --read-only \
        --cap-drop ALL \
        --security-opt no-new-privileges:true \
        --pids-limit 64 \
        --memory 64m \
        --cpus 0.25 \
        --user 65532:65532 \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=4m \
        hello-world:latest \
        >/dev/null 2>&1
    then
        ok "hardened Docker flags accepted"
    else
        bad "hardened Docker container failed"
    fi
else
    bad "hello-world image missing; run deploy-agent01-runtime.sh"
fi

section "Result"

if [[ "$ERRORS" -eq 0 ]]; then
    echo "agent01 verification PASS ✅"
    exit 0
fi

echo "agent01 verification FAIL: $ERRORS issue(s)"
exit 1
