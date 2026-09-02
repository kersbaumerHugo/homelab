#!/usr/bin/env bash
# Remote commands intentionally expand selected variables on the SSH client.
# shellcheck disable=SC2029
set -Eeuo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
CT_ID="${CT_ID:-100}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROM_CONFIG="$ROOT/monitoring/prometheus/prometheus.yml"
DEPLOY_SCRIPT="$ROOT/scripts/deploy-monitoring.sh"
VALIDATOR="$ROOT/scripts/validate-monitoring.sh"

EXPECTED_EXIT_CODE=42

TMP_ORIGINAL="$(mktemp)"

ok() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$1"
}

fail() {
    printf '\033[1;31m[FAIL]\033[0m %s\n' "$1" >&2
    exit 1
}

info() {
    printf '\n\033[1;34m==>\033[0m %s\n' "$1"
}

remote() {
    ssh "$PVE_HOST" \
        "pct exec $CT_ID -- bash -lc $(printf '%q' "$1")"
}

restore_local_config() {
    if [[ -f "$TMP_ORIGINAL" ]]; then
        cp "$TMP_ORIGINAL" "$PROM_CONFIG"
    fi
}

cleanup() {
    restore_local_config
    rm -f "$TMP_ORIGINAL"
}

trap cleanup EXIT

wait_for_health() {
    local name="$1"
    local url="$2"

    for attempt in {1..12}; do
        if remote "curl --fail --silent '$url'" >/dev/null 2>&1; then
            ok "$name healthy after rollback"
            return 0
        fi

        echo "Waiting for $name after rollback... ($attempt/12)"
        sleep 5
    done

    fail "$name did not recover after rollback"
}

echo
echo "========================================"
echo " Monitoring rollback test"
echo "========================================"

info "Checking prerequisites"

[[ -x "$DEPLOY_SCRIPT" ]] \
    || fail "Deploy script not executable"

[[ -x "$VALIDATOR" ]] \
    || fail "Validator not executable"

[[ -f "$PROM_CONFIG" ]] \
    || fail "Prometheus configuration not found"

git -C "$ROOT" diff --quiet -- "$PROM_CONFIG" \
    || fail "Prometheus configuration already has local changes"

git -C "$ROOT" diff --cached --quiet -- "$PROM_CONFIG" \
    || fail "Prometheus configuration has staged changes"

ssh -o BatchMode=yes "$PVE_HOST" true \
    || fail "Cannot reach $PVE_HOST"

CT_STATUS="$(ssh "$PVE_HOST" "pct status $CT_ID")"

grep -q 'status: running' <<< "$CT_STATUS" \
    || fail "Monitoring container is not running"

ok "Prerequisites satisfied"

info "Capturing known-good state"

cp "$PROM_CONFIG" "$TMP_ORIGINAL"

LOCAL_BEFORE="$(
    sha256sum "$PROM_CONFIG" |
        awk '{print $1}'
)"

REMOTE_BEFORE="$(
    remote \
        "sha256sum /etc/prometheus/prometheus.yml | awk '{print \$1}'"
)"

echo "Local  : $LOCAL_BEFORE"
echo "Runtime: $REMOTE_BEFORE"

[[ "$LOCAL_BEFORE" == "$REMOTE_BEFORE" ]] \
    || fail "Git/runtime drift exists before rollback test"

ok "Git and runtime initially match"

info "Creating harmless candidate configuration"

printf '\n# rollback-chaos-test %s\n' "$(date -Iseconds)" \
    >> "$PROM_CONFIG"

CANDIDATE_SHA="$(
    sha256sum "$PROM_CONFIG" |
        awk '{print $1}'
)"

[[ "$CANDIDATE_SHA" != "$LOCAL_BEFORE" ]] \
    || fail "Candidate configuration did not change"

"$VALIDATOR"

ok "Candidate is valid and differs from production"

info "Executing fault-injected deployment"

set +e

HOMELAB_FAULT_INJECTION=after-restart \
    "$DEPLOY_SCRIPT"

DEPLOY_RC=$?

set -e

echo
echo "Deployment exit code: $DEPLOY_RC"

[[ "$DEPLOY_RC" -eq "$EXPECTED_EXIT_CODE" ]] \
    || fail "Expected exit code $EXPECTED_EXIT_CODE, got $DEPLOY_RC"

ok "Deployment failed exactly at injected fault"

info "Checking service recovery"

PROM_STATUS="$(remote "systemctl is-active prometheus" || true)"
GRAFANA_STATUS="$(remote "systemctl is-active grafana-server" || true)"

[[ "$PROM_STATUS" == "active" ]] \
    || fail "Prometheus inactive after rollback"

[[ "$GRAFANA_STATUS" == "active" ]] \
    || fail "Grafana inactive after rollback"

ok "Services active after rollback"

wait_for_health \
    "Prometheus" \
    "http://127.0.0.1:9090/-/healthy"

wait_for_health \
    "Grafana" \
    "http://127.0.0.1:3000/api/health"

info "Verifying exact runtime restoration"

REMOTE_AFTER="$(
    remote \
        "sha256sum /etc/prometheus/prometheus.yml | awk '{print \$1}'"
)"

echo "Before: $REMOTE_BEFORE"
echo "After : $REMOTE_AFTER"

[[ "$REMOTE_BEFORE" == "$REMOTE_AFTER" ]] \
    || fail "Runtime configuration was not restored byte-for-byte"

ok "Runtime configuration restored exactly"

info "Restoring local repository"

restore_local_config

LOCAL_AFTER="$(
    sha256sum "$PROM_CONFIG" |
        awk '{print $1}'
)"

[[ "$LOCAL_BEFORE" == "$LOCAL_AFTER" ]] \
    || fail "Local Prometheus configuration was not restored"

"$VALIDATOR"

ok "Local repository restored and valid"

echo
echo "========================================"
printf '\033[1;32m Rollback test successful ✅\033[0m\n'
echo "========================================"
echo
echo "Proved:"
echo "  candidate deployed"
echo "  fault injected"
echo "  deployment failed"
echo "  rollback executed"
echo "  services recovered"
echo "  runtime restored byte-for-byte"
echo "  repository restored"
