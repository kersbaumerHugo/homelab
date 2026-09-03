#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYSTEMD_DIR="$ROOT/monitoring/node-exporter/systemd"

echo "==> Checking YAML"

find "$ROOT/monitoring" \
  -type f \
  \( -name '*.yml' -o -name '*.yaml' \) \
  -print0 |
while IFS= read -r -d '' file; do
    echo "Checking $file"
    python3 -c '
import sys, yaml
with open(sys.argv[1]) as f:
    yaml.safe_load(f)
' "$file"
done
echo "==> Checking Grafana alert state enums"

python3 - "$ROOT/monitoring/grafana/provisioning/alerting" <<'PY'
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
    data = yaml.safe_load(path.read_text()) or {}

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

echo "==> Checking for tabs in YAML"

if grep -RnP '\t' "$ROOT/monitoring" \
    --include='*.yml' \
    --include='*.yaml'; then

    echo "ERROR: tabs found in YAML"
    exit 1
fi

NODE_EXPORTER_ENV="$ROOT/monitoring/node-exporter/pve01.env"

echo "==> Checking Node Exporter configuration"

[[ -f "$NODE_EXPORTER_ENV" ]] || {
    echo "Missing Node Exporter configuration"
    exit 1
}

bash -n "$NODE_EXPORTER_ENV"

grep -q '^ARGS=' "$NODE_EXPORTER_ENV" || {
    echo "Node Exporter configuration does not define ARGS"
    exit 1
}

echo "==> Checking Python collectors"

find "$ROOT/monitoring/node-exporter" \
    -type f \
    -name '*.py' \
    -print0 |
while IFS= read -r -d '' file; do
    echo "Checking $file"

    python3 -c '
import ast
import pathlib
import sys

ast.parse(
    pathlib.Path(sys.argv[1]).read_text()
)
' "$file"
done


echo "==> Checking systemd units"

SYSTEMD_TMP="$(mktemp -d)"

cleanup_systemd_validation() {
    rm -rf "$SYSTEMD_TMP"
}

trap cleanup_systemd_validation RETURN

while IFS= read -r -d '' unit; do
    filename="$(basename "$unit")"
    cp "$unit" "$SYSTEMD_TMP/$filename"
done < <(
    find "$SYSTEMD_DIR" \
        -maxdepth 1 \
        -type f \
        \( -name '*.service' -o -name '*.timer' \) \
        -print0
)

for service in "$SYSTEMD_TMP"/*.service; do
    [[ -e "$service" ]] || continue

    sed -i \
        's#^ExecStart=.*#ExecStart=/bin/true#' \
        "$service"
done

systemd-analyze verify "$SYSTEMD_TMP"/*

rm -rf "$SYSTEMD_TMP"
trap - RETURN

echo "==> Checking Grafana dashboards"

find "$ROOT/monitoring/grafana/dashboards" \
    -type f \
    -name '*.json' \
    -exec jq empty {} \;

echo "==> Checking shell scripts"

shellcheck "$ROOT"/scripts/*.sh

echo "==> Checking Prometheus"

promtool check config \
    "$ROOT/monitoring/prometheus/prometheus.yml"

echo "==> Checking duplicate Grafana UIDs"

DUPLICATES="$(
    grep -RhoE \
      '^[[:space:]]+- uid: [^[:space:]]+' \
      "$ROOT/monitoring/grafana/provisioning/alerting" \
    | awk '{print $3}' \
    | sort \
    | uniq -d
)"

if [[ -n "$DUPLICATES" ]]; then
    echo "Duplicate Grafana UIDs:"
    echo "$DUPLICATES"
    exit 1
fi

echo "==> Checking datasource UIDs"

BAD_UIDS="$(
    grep -RhoE \
      'datasourceUid:[[:space:]]+[^[:space:]]+' \
      "$ROOT/monitoring/grafana/provisioning/alerting" \
    | awk '{print $2}' \
    | grep -Ev '^(prometheus|__expr__)$' \
    | sort -u || true
)"

if [[ -n "$BAD_UIDS" ]]; then
    echo "Unexpected datasource UIDs:"
    echo "$BAD_UIDS"
    exit 1
fi

echo
echo "Monitoring repository validation successful ✅"
