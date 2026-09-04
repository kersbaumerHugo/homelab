#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEMD_DIR="$ROOT/monitoring/node-exporter/systemd"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/validate-monitoring.sh [check ...]

Checks:
  yaml        YAML syntax and YAML tab hygiene
  collectors  Node Exporter config, Python collectors and systemd units
  shell       ShellCheck for repository shell scripts
  prometheus  Prometheus configuration validation
  grafana     Grafana alerts, dashboards and UID validation
  all         Run all checks (default)

Examples:
  ./scripts/validate-monitoring.sh
  ./scripts/validate-monitoring.sh grafana
  ./scripts/validate-monitoring.sh yaml prometheus
EOF
}

check_yaml() {
    echo "==> Checking YAML syntax"

    while IFS= read -r -d '' file; do
        echo "Checking $file"
        python3 -c '
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    yaml.safe_load(f)
' "$file"
    done < <(
        find "$ROOT/monitoring" \
            -type f \
            \( -name '*.yml' -o -name '*.yaml' \) \
            -print0
    )

    echo "==> Checking for tabs in YAML"

    if grep -RnP '\t' "$ROOT/monitoring" \
        --include='*.yml' \
        --include='*.yaml'; then
        echo "ERROR: tabs found in YAML"
        return 1
    fi

    echo "PASS: YAML"
}

check_collectors() {
    local node_exporter_env
    local systemd_tmp

    node_exporter_env="$ROOT/monitoring/node-exporter/pve01.env"

    echo "==> Checking Node Exporter configuration"

    [[ -f "$node_exporter_env" ]] || {
        echo "Missing Node Exporter configuration"
        return 1
    }

    bash -n "$node_exporter_env"

    grep -q '^ARGS=' "$node_exporter_env" || {
        echo "Node Exporter configuration does not define ARGS"
        return 1
    }

    echo "==> Checking Python collectors"

    while IFS= read -r -d '' file; do
        echo "Checking $file"

        python3 -c '
import ast
import pathlib
import sys

ast.parse(
    pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
)
' "$file"
    done < <(
        find "$ROOT/monitoring/node-exporter" \
            -type f \
            -name '*.py' \
            -print0
    )

    echo "==> Checking systemd units"

    systemd_tmp="$(mktemp -d)"

    cleanup_systemd_tmp() {
        rm -rf "$systemd_tmp"
    }

    trap cleanup_systemd_tmp RETURN

    while IFS= read -r -d '' unit; do
        cp "$unit" "$systemd_tmp/$(basename "$unit")"
    done < <(
        find "$SYSTEMD_DIR" \
            -maxdepth 1 \
            -type f \
            \( -name '*.service' -o -name '*.timer' \) \
            -print0
    )

    for service in "$systemd_tmp"/*.service; do
        [[ -e "$service" ]] || continue
        sed -i \
            's#^ExecStart=.*#ExecStart=/bin/true#' \
            "$service"
    done

    systemd-analyze verify "$systemd_tmp"/*

    rm -rf "$systemd_tmp"
    trap - RETURN

    echo "PASS: collectors"
}

check_shell() {
    echo "==> Checking shell scripts"
    shellcheck "$ROOT"/scripts/*.sh
    echo "PASS: shell"
}

check_prometheus() {
    echo "==> Checking Prometheus configuration"

    promtool check config \
        "$ROOT/monitoring/prometheus/prometheus.yml"

    echo "PASS: Prometheus"
}

check_grafana() {
    local alerting_dir
    local duplicates
    local bad_uids

    alerting_dir="$ROOT/monitoring/grafana/provisioning/alerting"

    echo "==> Checking Grafana alert state enums"

    python3 - "$alerting_dir" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])

valid_no_data = {
    "NoData",
    "Alerting",
    "OK",
    "KeepLastState",
}

valid_exec_error = {
    "Error",
    "Alerting",
    "OK",
    "KeepLastState",
}

for path in root.glob("*.yml"):
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}

    for group in data.get("groups", []):
        for rule in group.get("rules", []):
            title = rule.get("title", "<unknown>")

            no_data = rule.get("noDataState")
            if no_data not in valid_no_data:
                raise SystemExit(
                    f"{path}: rule {title!r}: "
                    f"invalid noDataState {no_data!r}"
                )

            exec_error = rule.get("execErrState")
            if exec_error not in valid_exec_error:
                raise SystemExit(
                    f"{path}: rule {title!r}: "
                    f"invalid execErrState {exec_error!r}"
                )

print("Grafana alert state enums valid")
PY

    echo "==> Checking Grafana dashboards"

    find "$ROOT/monitoring/grafana/dashboards" \
        -type f \
        -name '*.json' \
        -exec jq empty {} \;

    echo "==> Checking duplicate Grafana UIDs"

    duplicates="$(
        grep -RhoE \
            '^[[:space:]]+- uid: [^[:space:]]+' \
            "$alerting_dir" \
        | awk '{print $3}' \
        | sort \
        | uniq -d
    )"

    if [[ -n "$duplicates" ]]; then
        echo "Duplicate Grafana UIDs:"
        echo "$duplicates"
        return 1
    fi

    echo "==> Checking datasource UIDs"

    bad_uids="$(
        grep -RhoE \
            'datasourceUid:[[:space:]]+[^[:space:]]+' \
            "$alerting_dir" \
        | awk '{print $2}' \
        | grep -Ev '^(prometheus|__expr__)$' \
        | sort -u || true
    )"

    if [[ -n "$bad_uids" ]]; then
        echo "Unexpected datasource UIDs:"
        echo "$bad_uids"
        return 1
    fi

    echo "PASS: Grafana static validation"
}

run_check() {
    case "$1" in
        yaml)
            check_yaml
            ;;
        collectors)
            check_collectors
            ;;
        shell)
            check_shell
            ;;
        prometheus)
            check_prometheus
            ;;
        grafana)
            check_grafana
            ;;
        all)
            check_yaml
            check_collectors
            check_shell
            check_prometheus
            check_grafana
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "Unknown validation check: $1" >&2
            usage >&2
            return 2
            ;;
    esac
}

if (($# == 0)); then
    set -- all
fi

for check in "$@"; do
    run_check "$check"
done

echo
echo "Monitoring repository validation successful ✅"
