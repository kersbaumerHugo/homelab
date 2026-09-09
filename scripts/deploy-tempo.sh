#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PVE_HOST="${PVE_HOST:-pve01}"
VMID=101
TRACE_IP="192.168.10.20"

TEMPO_VERSION="3.0.3"
TEMPO_DEB="tempo_${TEMPO_VERSION}_linux_amd64.deb"
TEMPO_URL="https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/${TEMPO_DEB}"
TEMPO_SHA256="e544ba3e350a6f32854fbf655ea8be58dd0336a45571ca164360c9440fc44ff0"

CONFIG="$ROOT/monitoring/tempo/tempo.yml"
REMOTE_STAGE="/tmp/trace01-tempo-$$.yml"

DPKG_FORMAT="\${Version}"

DEPLOY_OK=0
HAD_CONFIG=0

remote() {
    local cmd
    printf -v cmd '%q ' "$@"
    printf '%s\n' "$cmd" |
        ssh -T "$PVE_HOST" 'bash -se'
}

ct() {
    remote pct exec "$VMID" -- "$@"
}

cleanup() {
    local rc=$?

    trap - EXIT

    ssh -T "$PVE_HOST" \
        "rm -f '$REMOTE_STAGE'" \
        >/dev/null 2>&1 || true

    if [[ "$DEPLOY_OK" -eq 0 ]]; then
        echo
        echo "[ROLLBACK] Tempo deployment failed."

        if [[ "$HAD_CONFIG" -eq 1 ]]; then
            ct bash -lc '
                if [[ -f /etc/tempo/config.yml.pre-deploy ]]; then
                    cp /etc/tempo/config.yml.pre-deploy \
                       /etc/tempo/config.yml
                    systemctl restart tempo.service || true
                fi
            ' || true

            echo "[ROLLBACK] Previous configuration restored."
        fi
    fi

    exit "$rc"
}

trap cleanup EXIT

[[ -f "$CONFIG" ]] || {
    echo "[ERROR] Missing $CONFIG"
    exit 1
}

echo "========================================"
echo " Tempo deployment"
echo "========================================"

echo "==> Preflight"

remote pct status "$VMID" |
    grep -q 'status: running'

echo "[OK] trace01 running"

ct getent hosts github.com >/dev/null
echo "[OK] DNS/network available"

if ct test -f /etc/tempo/config.yml; then
    HAD_CONFIG=1

    ct cp \
        /etc/tempo/config.yml \
        /etc/tempo/config.yml.pre-deploy
fi

echo
echo "==> Installing prerequisites"

ct bash -lc '
    apt-get update
    DEBIAN_FRONTEND=noninteractive \
      apt-get install -y ca-certificates curl
'

INSTALLED_VERSION="$(
    ct dpkg-query \
        -W \
        "-f=${DPKG_FORMAT}" \
        tempo \
        2>/dev/null || true
)"

if [[ "$INSTALLED_VERSION" != "$TEMPO_VERSION" ]]; then
    echo
    echo "==> Installing Tempo ${TEMPO_VERSION}"

    ct curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --output "/tmp/${TEMPO_DEB}" \
        "$TEMPO_URL"

    ct bash -lc \
        "echo '${TEMPO_SHA256}  /tmp/${TEMPO_DEB}' | sha256sum -c -"

    ct dpkg -i "/tmp/${TEMPO_DEB}"

    echo "[OK] Tempo ${TEMPO_VERSION} installed"
else
    echo "[OK] Tempo ${TEMPO_VERSION} already installed"
fi

echo
echo "==> Normalizing service account"

ct bash -lc '
    getent group tempo >/dev/null ||
        groupadd --system tempo

    if getent passwd tempo >/dev/null; then
        usermod \
          --gid tempo \
          --home /var/lib/tempo \
          --shell /usr/sbin/nologin \
          tempo
    else
        useradd \
          --system \
          --gid tempo \
          --home-dir /var/lib/tempo \
          --shell /usr/sbin/nologin \
          tempo
    fi
'

echo "[OK] tempo user/group normalized"

echo
echo "==> Preparing storage"

ct mkdir -p \
    /etc/tempo \
    /data/tempo/wal \
    /data/tempo/blocks \
    /var/lib/tempo

ct chown -R tempo:tempo \
    /data/tempo \
    /var/lib/tempo

echo
echo "==> Staging Git-managed configuration"

scp -q \
    "$CONFIG" \
    "${PVE_HOST}:${REMOTE_STAGE}"

remote pct push \
    "$VMID" \
    "$REMOTE_STAGE" \
    /etc/tempo/config.yml

ct chown root:root /etc/tempo/config.yml
ct chmod 0644 /etc/tempo/config.yml

echo "[OK] configuration deployed"

echo
echo "==> Validating Tempo configuration"

ct tempo \
    --config.file=/etc/tempo/config.yml \
    --config.verify=true

echo "[OK] configuration valid"

echo
echo "==> Restarting Tempo"

ct systemctl daemon-reload
ct systemctl enable tempo.service >/dev/null
ct systemctl restart tempo.service

for _ in $(seq 1 30); do
    if ct curl \
        --fail \
        --silent \
        http://127.0.0.1:3200/ready \
        >/dev/null 2>&1
    then
        break
    fi

    sleep 1
done

ct systemctl is-active --quiet tempo.service

ct curl \
    --fail \
    --silent \
    http://127.0.0.1:3200/ready \
    >/dev/null

echo "[OK] Tempo ready"

echo
echo "==> Verifying listeners"

ct bash -lc '
    ss -ltn |
      grep -q ":3200 " &&
    ss -ltn |
      grep -q ":4317 "
'

echo "[OK] :3200 HTTP"
echo "[OK] :4317 OTLP gRPC"

remote curl \
    --fail \
    --silent \
    "http://${TRACE_IP}:3200/ready" \
    >/dev/null

echo "[OK] Tempo reachable from pve01"

echo
echo "==> Regression check"

"$ROOT/scripts/verify-monitoring.sh"

ct rm -f /etc/tempo/config.yml.pre-deploy

DEPLOY_OK=1

echo
echo "========================================"
echo " Tempo deployment successful ✅"
echo " Existing monitoring remains healthy ✅"
echo "========================================"
