#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LVM_SERVICE="$ROOT/monitoring/node-exporter/systemd/homelab-lvm-collector.service"
LVM_TIMER="$ROOT/monitoring/node-exporter/systemd/homelab-lvm-collector.timer"
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


echo "==> Checking systemd units"

for file in "$LVM_SERVICE" "$LVM_TIMER"; do
    [[ -f "$file" ]] || {
        echo "Missing systemd unit: $file"
        exit 1
    }
done

SYSTEMD_TMP="$(mktemp -d)"

cleanup_systemd_validation() {
    rm -rf "$SYSTEMD_TMP"
}
trap cleanup_systemd_validation RETURN

cp "$LVM_SERVICE" \
    "$SYSTEMD_TMP/homelab-lvm-collector.service"

cp "$LVM_TIMER" \
    "$SYSTEMD_TMP/homelab-lvm-collector.timer"

# The CI runner does not have the production collector installed.
# Replace only ExecStart so systemd-analyze can validate unit semantics.
sed -i \
    's#^ExecStart=.*#ExecStart=/bin/true#' \
    "$SYSTEMD_TMP/homelab-lvm-collector.service"

systemd-analyze verify \
    "$SYSTEMD_TMP/homelab-lvm-collector.service" \
    "$SYSTEMD_TMP/homelab-lvm-collector.timer"

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
