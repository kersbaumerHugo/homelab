#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-pve01}"
CONFIG="$ROOT/proxmox/pve01/guests/agent01.yml"

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

read -r VMID NAME DOCKER_VERSION < <(
    python3 - "$CONFIG" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))

print(
    data["vmid"],
    data["name"],
    data["runtime"]["docker_engine_version"],
)
PY
)

echo "========================================"
echo " agent01 container runtime deployment"
echo "========================================"
echo "PVE host       : $PVE_HOST"
echo "VMID           : $VMID"
echo "Hostname       : $NAME"
echo "Docker version : $DOCKER_VERSION"
echo

echo "==> Preflight"

remote pct status "$VMID" | grep -q 'status: running'

ACTUAL_NAME="$(
    remote pct config "$VMID" |
        awk '$1 == "hostname:" { print $2 }'
)"

if [[ "$ACTUAL_NAME" != "$NAME" ]]; then
    echo "[ERROR] VMID $VMID belongs to '$ACTUAL_NAME', expected '$NAME'"
    exit 1
fi

ct bash -lc "grep -q '^VERSION_ID=\"13\"$' /etc/os-release"

echo "[OK] agent01 running on Debian 13"

echo
echo "==> Installing Docker repository prerequisites"

DEBIAN_CODENAME="$(
    ct grep '^VERSION_CODENAME=' /etc/os-release |
        cut -d= -f2- |
        tr -d '"'
)"

if [[ -z "$DEBIAN_CODENAME" ]]; then
    echo "[ERROR] Could not determine Debian codename"
    exit 1
fi

ct bash -lc "
    apt-get update

    DEBIAN_FRONTEND=noninteractive \
      apt-get install -y ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL \
      https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${DEBIAN_CODENAME}
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt-get update
"

echo "[OK] Docker APT repository configured"

echo
echo "==> Resolving pinned Docker Engine package"

ENGINE_APT_VERSION="$(
    ct bash -lc \
        "apt-cache madison docker-ce | awk '\$3 ~ /${DOCKER_VERSION}/ { print \$3; exit }'"
)"

CLI_APT_VERSION="$(
    ct bash -lc \
        "apt-cache madison docker-ce-cli | awk '\$3 ~ /${DOCKER_VERSION}/ { print \$3; exit }'"
)"

if [[ -z "$ENGINE_APT_VERSION" ]]; then
    echo "[ERROR] docker-ce $DOCKER_VERSION is unavailable"
    exit 1
fi

if [[ -z "$CLI_APT_VERSION" ]]; then
    echo "[ERROR] docker-ce-cli $DOCKER_VERSION is unavailable"
    exit 1
fi

echo "[OK] docker-ce package: $ENGINE_APT_VERSION"
echo "[OK] docker-ce-cli package: $CLI_APT_VERSION"

echo
echo "==> Reconciling Docker Engine"

ct bash -lc "
    apt-mark unhold docker-ce docker-ce-cli >/dev/null 2>&1 || true

    DEBIAN_FRONTEND=noninteractive \
      apt-get install -y \
        docker-ce='${ENGINE_APT_VERSION}' \
        docker-ce-cli='${CLI_APT_VERSION}' \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    apt-mark hold docker-ce docker-ce-cli >/dev/null

    systemctl enable docker.service >/dev/null
    systemctl enable containerd.service >/dev/null
    systemctl restart docker.service
"

echo "[OK] Docker packages reconciled"

echo
echo "==> Verifying Docker service"

ct systemctl is-active --quiet docker.service
ct systemctl is-enabled --quiet docker.service

echo "[OK] docker.service active and enabled"

echo
echo "==> Verifying Docker Engine version"

ACTUAL_VERSION="$(
    ct docker version --format '{{.Server.Version}}'
)"

if [[ "$ACTUAL_VERSION" != "$DOCKER_VERSION" ]]; then
    echo "[ERROR] Docker version drift: expected $DOCKER_VERSION, got $ACTUAL_VERSION"
    exit 1
fi

echo "[OK] Docker Engine $ACTUAL_VERSION"

echo
echo "==> Verifying runtime properties"

DOCKER_INFO="$(
    ct docker info --format \
        '{{.Driver}}|{{.CgroupDriver}}|{{.CgroupVersion}}|{{json .SecurityOptions}}'
)"

IFS='|' read -r \
    STORAGE_DRIVER \
    CGROUP_DRIVER \
    CGROUP_VERSION \
    SECURITY_OPTIONS <<< "$DOCKER_INFO"

[[ "$STORAGE_DRIVER" == "overlayfs" ]]
[[ "$CGROUP_DRIVER" == "systemd" ]]
[[ "$CGROUP_VERSION" == "2" ]]
grep -q 'seccomp' <<< "$SECURITY_OPTIONS"

echo "[OK] storage driver: $STORAGE_DRIVER"
echo "[OK] cgroup driver: $CGROUP_DRIVER"
echo "[OK] cgroup version: $CGROUP_VERSION"
echo "[OK] seccomp available"

echo
echo "==> Functional container smoke"

ct docker run --rm hello-world >/dev/null

echo "[OK] hello-world lifecycle"

echo
echo "========================================"
echo " agent01 Docker runtime deployment successful ✅"
echo "========================================"
