#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PVE_HOST="${PVE_HOST:-pve01}"
VMID="${AGENT_CT_ID:-102}"
AGENT_IP="${AGENT_PLATFORM_IP:-192.168.10.30}"
RELEASE="${AGENT_PLATFORM_RELEASE:-v0.1.0}"

BASE_DIR="/opt/agent-platform"
RELEASE_DIR="${BASE_DIR}/releases/${RELEASE}"
CURRENT_LINK="${BASE_DIR}/current"

API_UNIT_LOCAL="$ROOT/systemd/agent-platform-api.service"
MCP_UNIT_LOCAL="$ROOT/systemd/agent-platform-mcp.service"

PVE_API_STAGE="/tmp/agent-platform-api-$$.service"
PVE_MCP_STAGE="/tmp/agent-platform-mcp-$$.service"

API_UNIT_REMOTE="/etc/systemd/system/agent-platform-api.service"
MCP_UNIT_REMOTE="/etc/systemd/system/agent-platform-mcp.service"

DEPLOY_OK=0
HAD_CURRENT=0
PREVIOUS_CURRENT=""
HAD_API_UNIT=0
HAD_MCP_UNIT=0

remote() {
    local cmd
    printf -v cmd '%q ' "$@"
    printf '%s\n' "$cmd" | ssh -T "$PVE_HOST" 'bash -se'
}

ct() {
    remote pct exec "$VMID" -- "$@"
}

cleanup() {
    local rc=$?

    trap - EXIT

    ssh -T "$PVE_HOST" \
        "rm -f '$PVE_API_STAGE' '$PVE_MCP_STAGE'" \
        >/dev/null 2>&1 || true

    if [[ "$DEPLOY_OK" -eq 0 ]]; then
        echo
        echo "[ROLLBACK] systemd lifecycle deployment failed."

        if [[ "$HAD_API_UNIT" -eq 1 ]]; then
            ct bash -lc \
                "cp '${API_UNIT_REMOTE}.pre-deploy' '$API_UNIT_REMOTE'" \
                || true
        else
            ct rm -f "$API_UNIT_REMOTE" || true
        fi

        if [[ "$HAD_MCP_UNIT" -eq 1 ]]; then
            ct bash -lc \
                "cp '${MCP_UNIT_REMOTE}.pre-deploy' '$MCP_UNIT_REMOTE'" \
                || true
        else
            ct rm -f "$MCP_UNIT_REMOTE" || true
        fi

        if [[ "$HAD_CURRENT" -eq 1 ]]; then
            ct ln -sfn "$PREVIOUS_CURRENT" "${CURRENT_LINK}.rollback" || true
            ct mv -Tf "${CURRENT_LINK}.rollback" "$CURRENT_LINK" || true
        else
            ct rm -f "$CURRENT_LINK" || true
        fi

        ct systemctl daemon-reload || true

        if [[ "$HAD_API_UNIT" -eq 1 ]]; then
            ct systemctl restart agent-platform-api.service || true
        else
            ct systemctl disable --now agent-platform-api.service \
                >/dev/null 2>&1 || true
        fi

        if [[ "$HAD_MCP_UNIT" -eq 1 ]]; then
            ct systemctl restart agent-platform-mcp.service || true
        else
            ct systemctl disable --now agent-platform-mcp.service \
                >/dev/null 2>&1 || true
        fi

        echo "[ROLLBACK] previous lifecycle state restored where available."
    else
        ct rm -f \
            "${API_UNIT_REMOTE}.pre-deploy" \
            "${MCP_UNIT_REMOTE}.pre-deploy" \
            >/dev/null 2>&1 || true
    fi

    exit "$rc"
}

trap cleanup EXIT

[[ -f "$API_UNIT_LOCAL" ]] || {
    echo "[ERROR] Missing $API_UNIT_LOCAL"
    exit 1
}

[[ -f "$MCP_UNIT_LOCAL" ]] || {
    echo "[ERROR] Missing $MCP_UNIT_LOCAL"
    exit 1
}

echo "========================================"
echo " Agent Platform systemd lifecycle"
echo "========================================"
echo "PVE host : $PVE_HOST"
echo "VMID     : $VMID"
echo "Release  : $RELEASE"
echo "IP       : $AGENT_IP"
echo

echo "==> Preflight"

remote pct status "$VMID" |
    grep -q 'status: running'

ct test -d "$RELEASE_DIR"
ct test -x "${RELEASE_DIR}/.venv/bin/python"
ct "${RELEASE_DIR}/.venv/bin/python" -m uvicorn --version >/dev/null
ct test -s "${RELEASE_DIR}/REVISION"

ct test -s /etc/agent-platform/api.env
ct test -s /etc/agent-platform/mcp.env

echo "[OK] agent01 running"
echo "[OK] release present"
echo "[OK] runtime configuration present"

if ct test -L "$CURRENT_LINK"; then
    HAD_CURRENT=1
    PREVIOUS_CURRENT="$(ct readlink -f "$CURRENT_LINK")"
elif ct test -e "$CURRENT_LINK"; then
    echo "[ERROR] $CURRENT_LINK exists but is not a symbolic link."
    exit 1
fi

if ct test -f "$API_UNIT_REMOTE"; then
    HAD_API_UNIT=1
    ct cp "$API_UNIT_REMOTE" "${API_UNIT_REMOTE}.pre-deploy"
fi

if ct test -f "$MCP_UNIT_REMOTE"; then
    HAD_MCP_UNIT=1
    ct cp "$MCP_UNIT_REMOTE" "${MCP_UNIT_REMOTE}.pre-deploy"
fi

echo
echo "==> Activating release pointer"

ct ln -sfn "$RELEASE_DIR" "${CURRENT_LINK}.new"
ct mv -Tf "${CURRENT_LINK}.new" "$CURRENT_LINK"

ACTIVE_REVISION="$(ct cat "${CURRENT_LINK}/REVISION")"

echo "[OK] current -> $RELEASE_DIR"
echo "[OK] active revision: $ACTIVE_REVISION"

echo
echo "==> Staging systemd units"

scp -q \
    "$API_UNIT_LOCAL" \
    "${PVE_HOST}:${PVE_API_STAGE}"

scp -q \
    "$MCP_UNIT_LOCAL" \
    "${PVE_HOST}:${PVE_MCP_STAGE}"

remote pct push \
    "$VMID" \
    "$PVE_API_STAGE" \
    "$API_UNIT_REMOTE"

remote pct push \
    "$VMID" \
    "$PVE_MCP_STAGE" \
    "$MCP_UNIT_REMOTE"

ct chown root:root \
    "$API_UNIT_REMOTE" \
    "$MCP_UNIT_REMOTE"

ct chmod 0644 \
    "$API_UNIT_REMOTE" \
    "$MCP_UNIT_REMOTE"

echo "[OK] unit files deployed"

echo
echo "==> Validating unit files"

ct systemd-analyze verify \
    "$API_UNIT_REMOTE" \
    "$MCP_UNIT_REMOTE"

echo "[OK] systemd unit validation passed"

echo
echo "==> Enabling and starting services"

ct systemctl daemon-reload

ct systemctl reset-failed \
    agent-platform-api.service \
    agent-platform-mcp.service \
    >/dev/null 2>&1 || true

ct systemctl enable \
    agent-platform-api.service \
    agent-platform-mcp.service \
    >/dev/null

ct systemctl restart \
    agent-platform-api.service \
    agent-platform-mcp.service

echo "[OK] services enabled and restart requested"

echo
echo "==> Waiting for health"

for _ in $(seq 1 30); do
    if ct curl \
        --fail \
        --silent \
        "http://${AGENT_IP}:8000/health" \
        >/dev/null 2>&1 &&
       ct curl \
        --fail \
        --silent \
        "http://${AGENT_IP}:8001/metrics" \
        >/dev/null 2>&1
    then
        break
    fi

    sleep 1
done

ct systemctl is-active --quiet agent-platform-api.service
ct systemctl is-active --quiet agent-platform-mcp.service

ct curl \
    --fail \
    --silent \
    "http://${AGENT_IP}:8000/health" \
    >/dev/null

ct curl \
    --fail \
    --silent \
    "http://${AGENT_IP}:8000/metrics" \
    >/dev/null

ct curl \
    --fail \
    --silent \
    "http://${AGENT_IP}:8001/metrics" \
    >/dev/null

echo "[OK] API active and healthy"
echo "[OK] MCP active and metrics available"

echo
echo "==> Verifying listeners"

ct bash -lc "
    ss -ltn |
      grep -q '${AGENT_IP}:8000 ' &&
    ss -ltn |
      grep -q '${AGENT_IP}:8001 '
"

echo "[OK] API bound explicitly to ${AGENT_IP}:8000"
echo "[OK] MCP bound explicitly to ${AGENT_IP}:8001"

echo
echo "==> Verifying reachability from pve01"

remote curl \
    --fail \
    --silent \
    "http://${AGENT_IP}:8000/health" \
    >/dev/null

remote curl \
    --fail \
    --silent \
    "http://${AGENT_IP}:8001/metrics" \
    >/dev/null

echo "[OK] pve01 can reach API and MCP"

echo
echo "==> Verifying reachability from mon01"

remote pct exec 100 -- \
    curl \
      --fail \
      --silent \
      "http://${AGENT_IP}:8000/metrics" \
      >/dev/null

remote pct exec 100 -- \
    curl \
      --fail \
      --silent \
      "http://${AGENT_IP}:8001/metrics" \
      >/dev/null

echo "[OK] mon01 can reach both metrics endpoints"

echo
echo "==> Lifecycle evidence"

ct systemctl show \
    agent-platform-api.service \
    agent-platform-mcp.service \
    -p Id \
    -p ActiveState \
    -p SubState \
    -p UnitFileState \
    -p Restart \
    -p RestartUSec \
    -p StartLimitBurst

echo
echo "==> Recent service logs"

ct journalctl \
    -u agent-platform-api.service \
    -u agent-platform-mcp.service \
    -n 20 \
    --no-pager

echo
echo "==> Existing monitoring regression"

"$ROOT/scripts/verify-monitoring.sh"

DEPLOY_OK=1

echo
echo "========================================"
echo " Phase 4 systemd lifecycle successful ✅"
echo " Gate P4 persistent lifecycle proven ✅"
echo " Existing monitoring remains healthy ✅"
echo "========================================"
