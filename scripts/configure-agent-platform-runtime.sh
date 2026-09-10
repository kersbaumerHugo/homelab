#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
VMID="${AGENT_CT_ID:-102}"

RELEASE="${AGENT_PLATFORM_RELEASE:-v0.1.0}"
RELEASE_DIR="/opt/agent-platform/releases/${RELEASE}"

SOURCE_ENV="${AGENT_PLATFORM_SOURCE_ENV:-$HOME/Documents/agent-platform/.env}"

API_ENV_LOCAL="$(mktemp)"
MCP_ENV_LOCAL="$(mktemp)"
PVE_API_STAGE="/tmp/agent-platform-api-${VMID}-$$.env"
PVE_MCP_STAGE="/tmp/agent-platform-mcp-${VMID}-$$.env"

umask 077

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

    rm -f \
        "$API_ENV_LOCAL" \
        "$MCP_ENV_LOCAL"

    ssh -T "$PVE_HOST" \
        "rm -f '$PVE_API_STAGE' '$PVE_MCP_STAGE'" \
        >/dev/null 2>&1 || true

    exit "$rc"
}

trap cleanup EXIT

escape_env_value() {
    local value="$1"

    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        echo "[ERROR] Runtime environment values must not contain newlines." >&2
        return 1
    fi

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    printf '"%s"' "$value"
}

echo "========================================"
echo " Agent Platform runtime identity/config"
echo "========================================"
echo "PVE host : $PVE_HOST"
echo "VMID     : $VMID"
echo "Release  : $RELEASE"
echo

echo "==> Preflight"

remote pct status "$VMID" |
    grep -q 'status: running'

ct test -x "${RELEASE_DIR}/.venv/bin/python"
ct test -s "${RELEASE_DIR}/REVISION"

echo "[OK] agent01 running"
echo "[OK] release installed"

if [[ -z "${OPENROUTER_API_KEY:-}" ||
      -z "${MODEL_GATEWAY_API_KEY:-}" ]]; then
    if [[ ! -f "$SOURCE_ENV" ]]; then
        echo "[ERROR] Required credentials are not exported and source env file is missing:"
        echo "        $SOURCE_ENV"
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$SOURCE_ENV"
    set +a
fi

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is required}"
: "${MODEL_GATEWAY_API_KEY:?MODEL_GATEWAY_API_KEY is required}"

OPENROUTER_MODEL="${OPENROUTER_MODEL:-openrouter/free}"

echo "[OK] required runtime credentials available locally"

echo
echo "==> Preparing dedicated workload identity"

ct bash -lc '
    set -euo pipefail

    getent group agent-platform >/dev/null ||
        groupadd --system agent-platform

    if getent passwd agent-platform >/dev/null; then
        usermod \
          --gid agent-platform \
          --home /var/lib/agent-platform \
          --shell /usr/sbin/nologin \
          agent-platform
    else
        useradd \
          --system \
          --gid agent-platform \
          --home-dir /var/lib/agent-platform \
          --shell /usr/sbin/nologin \
          agent-platform
    fi

    install \
      -d \
      -o agent-platform \
      -g agent-platform \
      -m 0750 \
      /var/lib/agent-platform

    install \
      -d \
      -o root \
      -g root \
      -m 0755 \
      /etc/agent-platform
'

echo "[OK] dedicated non-login workload identity ready"

echo
echo "==> Building least-privilege runtime environment"

{
    printf 'OPENROUTER_API_KEY='
    escape_env_value "$OPENROUTER_API_KEY"
    printf '\n'

    printf 'MODEL_GATEWAY_API_KEY='
    escape_env_value "$MODEL_GATEWAY_API_KEY"
    printf '\n'

    printf 'OPENROUTER_MODEL='
    escape_env_value "$OPENROUTER_MODEL"
    printf '\n'

    printf '%s\n' \
        'OTEL_TRACES_EXPORTER="otlp"' \
        'OTEL_EXPORTER_OTLP_ENDPOINT="http://192.168.10.20:4317"' \
        'OTEL_EXPORTER_OTLP_INSECURE="true"' \
        'PYTHONUNBUFFERED="1"'
} > "$API_ENV_LOCAL"

{
    printf '%s\n' \
        'OTEL_TRACES_EXPORTER="otlp"' \
        'OTEL_EXPORTER_OTLP_ENDPOINT="http://192.168.10.20:4317"' \
        'OTEL_EXPORTER_OTLP_INSECURE="true"' \
        'PYTHONUNBUFFERED="1"'
} > "$MCP_ENV_LOCAL"

chmod 0600 \
    "$API_ENV_LOCAL" \
    "$MCP_ENV_LOCAL"

echo "[OK] API and MCP environments separated"
echo "[OK] MCP environment receives no model-provider credentials"

echo
echo "==> Staging runtime configuration"

scp -q \
    "$API_ENV_LOCAL" \
    "${PVE_HOST}:${PVE_API_STAGE}"

scp -q \
    "$MCP_ENV_LOCAL" \
    "${PVE_HOST}:${PVE_MCP_STAGE}"

remote chmod 0600 \
    "$PVE_API_STAGE" \
    "$PVE_MCP_STAGE"

remote pct push \
    "$VMID" \
    "$PVE_API_STAGE" \
    /etc/agent-platform/api.env

remote pct push \
    "$VMID" \
    "$PVE_MCP_STAGE" \
    /etc/agent-platform/mcp.env

ct chown root:root \
    /etc/agent-platform/api.env \
    /etc/agent-platform/mcp.env

ct chmod 0600 \
    /etc/agent-platform/api.env \
    /etc/agent-platform/mcp.env

echo "[OK] runtime configuration deployed outside Git"

echo
echo "==> Verifying permissions and required keys"

[[ "$(
    ct stat -c '%U:%G %a' /etc/agent-platform/api.env
)" == "root:root 600" ]]

[[ "$(
    ct stat -c '%U:%G %a' /etc/agent-platform/mcp.env
)" == "root:root 600" ]]

ct grep -q '^OPENROUTER_API_KEY=' \
    /etc/agent-platform/api.env

ct grep -q '^MODEL_GATEWAY_API_KEY=' \
    /etc/agent-platform/api.env

ct grep -q '^OPENROUTER_MODEL=' \
    /etc/agent-platform/api.env

if ct grep -Eq \
    '^(OPENROUTER_API_KEY|MODEL_GATEWAY_API_KEY)=' \
    /etc/agent-platform/mcp.env
then
    echo "[ERROR] MCP environment unexpectedly contains model credentials."
    exit 1
fi

echo "[OK] root-owned 0600 runtime files"
echo "[OK] required API keys present"
echo "[OK] model credentials absent from MCP environment"

echo
echo "==> Verifying workload identity can execute the release"

ct runuser \
    -u agent-platform \
    -- \
    "${RELEASE_DIR}/.venv/bin/python" \
    -c 'import agent_platform'

ct bash -lc "
    getent passwd agent-platform |
      awk -F: '\$7 == \"/usr/sbin/nologin\" { found=1 } END { exit !found }'
"

echo "[OK] workload identity executes Agent Platform"
echo "[OK] interactive login disabled"

echo
echo "==> Evidence"

echo "Identity:"
ct getent passwd agent-platform |
    awk -F: '{print "  user=" $1 ", uid=" $3 ", gid=" $4 ", home=" $6 ", shell=" $7}'

echo "Runtime files:"
ct stat \
    -c '  %n owner=%U:%G mode=%a' \
    /etc/agent-platform/api.env \
    /etc/agent-platform/mcp.env

echo "API environment:"
echo "  provider credential: present"
echo "  gateway credential: present"
echo "  model selection: explicit"
echo "  OTLP export: configured"

echo "MCP environment:"
echo "  provider credential: absent"
echo "  gateway credential: absent"
echo "  OTLP export: configured"

echo
echo "========================================"
echo " Phase 3 runtime configuration successful ✅"
echo " Gate P3 non-interactive secret delivery proven ✅"
echo "========================================"
