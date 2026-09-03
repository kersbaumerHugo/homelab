#!/usr/bin/env bash
# Remote commands intentionally expand selected variables on the SSH client.
# shellcheck disable=SC2029
set -u -o pipefail

PVE_HOST="${PVE_HOST:-pve01}"
CT_ID="${CT_ID:-100}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NODE_EXPORTER_ENV="$REPO_ROOT/monitoring/node-exporter/pve01.env"

PROM_CONFIG="$REPO_ROOT/monitoring/prometheus/prometheus.yml"
PROM_OVERRIDE="$REPO_ROOT/monitoring/prometheus/systemd/override.conf"

GRAFANA_DATASOURCE="$REPO_ROOT/monitoring/grafana/provisioning/datasources/prometheus.yml"
GRAFANA_PROVIDER="$REPO_ROOT/monitoring/grafana/provisioning/dashboards/homelab.yml"
GRAFANA_DASHBOARDS="$REPO_ROOT/monitoring/grafana/dashboards"
GRAFANA_ALERTING="$REPO_ROOT/monitoring/grafana/provisioning/alerting"

NTFY_CONFIG="$REPO_ROOT/monitoring/ntfy/server.yml"

FAILURES=0

ok() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$1"
}

bad() {
    printf '\033[1;31m[FAIL]\033[0m %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

section() {
    printf '\n\033[1;34m==> %s\033[0m\n' "$1"
}

remote() {
    ssh "$PVE_HOST" \
        "pct exec $CT_ID -- bash -lc $(printf '%q' "$1")"
}

host_service() {
    local service="$1"

    if [[ "$(ssh "$PVE_HOST" "systemctl is-active '$service'" 2>/dev/null)" == "active" ]]; then
        ok "$service active on pve01"
    else
        bad "$service inactive on pve01"
    fi
}

ct_service() {
    local service="$1"

    if [[ "$(remote "systemctl is-active '$service'" 2>/dev/null)" == "active" ]]; then
        ok "$service active on mon01"
    else
        bad "$service inactive on mon01"
    fi
}

prom_metric() {
    local query="$1"
    local description="$2"

    local output
    output="$(
        remote \
            "promtool query instant http://127.0.0.1:9090 '$query'" \
            2>/dev/null || true
    )"

    if grep -q '=>' <<< "$output"; then
        ok "$description"
    else
        bad "$description missing"
    fi
}

verify_sync() {
    local local_file="$1"
    local remote_file="$2"
    local description="$3"

    if [[ ! -f "$local_file" ]]; then
        bad "$description missing from repository"
        return
    fi

    local local_sha
    local remote_sha

    local_sha="$(sha256sum "$local_file" | awk '{print $1}')"

    remote_sha="$(
        remote \
            "sha256sum '$remote_file' 2>/dev/null | awk '{print \$1}'" \
            2>/dev/null || true
    )"

    if [[ -z "$remote_sha" ]]; then
        bad "$description missing from mon01"
    elif [[ "$local_sha" == "$remote_sha" ]]; then
        ok "$description synchronized"
    else
        bad "$description drift detected"
    fi
}

verify_host_sync() {
    local local_file="$1"
    local remote_file="$2"
    local description="$3"

    local local_sha
    local remote_sha

    local_sha="$(sha256sum "$local_file" | awk '{print $1}')"

    remote_sha="$(
        ssh "$PVE_HOST" \
            "sha256sum '$remote_file' 2>/dev/null | awk '{print \$1}'" \
            2>/dev/null || true
    )"

    if [[ -z "$remote_sha" ]]; then
        bad "$description missing from pve01"
    elif [[ "$local_sha" == "$remote_sha" ]]; then
        ok "$description synchronized"
    else
        bad "$description drift detected"
    fi
}

check_http_health() {
    local name="$1"
    local url="$2"
    local attempts="${3:-12}"
    local delay="${4:-5}"

    for attempt in $(seq 1 "$attempts"); do
        if remote "curl --fail --silent '$url'" >/dev/null 2>&1; then
            ok "$name healthy"
            return 0
        fi

        if (( attempt < attempts )); then
            echo "Waiting for $name... ($attempt/$attempts)"
            sleep "$delay"
        fi
    done

    bad "$name health endpoint failed"
    return 1
}
echo
echo "========================================"
echo " Homelab monitoring verification"
echo "========================================"

section "Connectivity"

if ! ssh -o BatchMode=yes "$PVE_HOST" true 2>/dev/null; then
    echo
    bad "Cannot reach $PVE_HOST using SSH key"
    echo
    echo "Cannot continue without pve01 connectivity."
    exit 2
fi

ok "pve01 reachable via SSH"

CT_STATUS="$(ssh "$PVE_HOST" "pct status $CT_ID" 2>/dev/null || true)"

if grep -q 'status: running' <<< "$CT_STATUS"; then
    ok "mon01 running"
else
    bad "mon01 is not running"
    echo
    echo "Cannot continue without mon01."
    exit 2
fi

section "Host services"

host_service prometheus-node-exporter
host_service smartmontools
if [[ "$(ssh "$PVE_HOST" \
    "systemctl is-active homelab-lvm-collector.timer" \
    2>/dev/null)" == "active" ]]; then

    ok "LVM collector timer active"
else
    bad "LVM collector timer inactive"
fi


section "Monitoring services"

ct_service prometheus
ct_service grafana-server
ct_service ntfy

section "Health endpoints"

check_http_health \
    "Prometheus" \
    "http://127.0.0.1:9090/-/healthy"

check_http_health \
    "Grafana" \
    "http://127.0.0.1:3000/api/health"

check_http_health \
    "ntfy" \
    "http://127.0.0.1/v1/health"

section "Prometheus"

if remote \
    "promtool check config /etc/prometheus/prometheus.yml" \
    >/dev/null 2>&1; then
    ok "Prometheus configuration valid"
else
    bad "Prometheus configuration invalid"
fi

TARGET="$(
    remote \
        "promtool query instant http://127.0.0.1:9090 'up{job=\"pve01\"}'" \
        2>/dev/null || true
)"

if grep -q '=> 1' <<< "$TARGET"; then
    ok "pve01 metrics target UP"
else
    bad "pve01 metrics target DOWN"
fi

section "Required metrics"

prom_metric \
    'max(node_hwmon_temp_celsius{instance="192.168.10.10:9100",chip="platform_coretemp_0"})' \
    "CPU temperature metric available"

prom_metric \
    'node_memory_MemAvailable_bytes{instance="192.168.10.10:9100"}' \
    "Memory metric available"

prom_metric \
    'node_filesystem_size_bytes{instance="192.168.10.10:9100",mountpoint="/"}' \
    "Root filesystem metric available"

prom_metric \
    'node_filesystem_size_bytes{instance="192.168.10.10:9100",mountpoint="/mnt/pve/hdd-backup"}' \
    "Backup filesystem metric available"
    
prom_metric \
    'homelab_lvm_collector_success{instance="192.168.10.10:9100"} == 1' \
    "LVM collector healthy"

prom_metric \
    'homelab_lvm_thin_data_percent{instance="192.168.10.10:9100",vg="pve",lv="data"}' \
    "LVM thin data metric available"

prom_metric \
    'homelab_lvm_thin_metadata_percent{instance="192.168.10.10:9100",vg="pve",lv="data"}' \
    "LVM thin metadata metric available"

prom_metric \
    'homelab_lvm_thin_size_bytes{instance="192.168.10.10:9100",vg="pve",lv="data"}' \
    "LVM thin size metric available"
    
prom_metric \
    'time() - homelab_lvm_collector_last_run_unixtime{instance="192.168.10.10:9100"} < 180' \
    "LVM collector metric fresh"

section "Systemd health"

FAILED_HOST="$(
    ssh "$PVE_HOST" \
        "systemctl show --property=NFailedUnits --value" \
        2>/dev/null || echo unknown
)"

if [[ "$FAILED_HOST" =~ ^[0-9]+$ ]] && (( FAILED_HOST == 0 )); then
    ok "pve01 has no failed systemd units"
else
    ssh "$PVE_HOST" "systemctl --failed --no-pager" || true
    bad "pve01 has failed systemd units: $FAILED_HOST"
fi

FAILED_CT="$(
    remote \
        "systemctl show --property=NFailedUnits --value" \
        2>/dev/null || echo unknown
)"

if [[ "$FAILED_CT" =~ ^[0-9]+$ ]] && (( FAILED_CT == 0 )); then
    ok "mon01 has no failed systemd units"
else
    remote "systemctl --failed --no-pager" || true
    bad "mon01 has failed systemd units: $FAILED_CT"
fi

section "Proxmox storage"

PVE_STORAGE="$(ssh "$PVE_HOST" "pvesm status" 2>/dev/null)"

for storage in local local-lvm hdd-backup; do
    if grep -Eq \
        "^${storage}[[:space:]]+[^[:space:]]+[[:space:]]+active" \
        <<< "$PVE_STORAGE"; then
        ok "$storage active"
    else
        bad "$storage unavailable"
    fi
done

section "Disk SMART"

for disk in /dev/sda /dev/sdb; do
    SMART="$(
        ssh "$PVE_HOST" \
            "smartctl -H '$disk'" \
            2>/dev/null || true
    )"

    if grep -q 'PASSED' <<< "$SMART"; then
        ok "$disk SMART PASSED"
    else
        bad "$disk SMART health failed"
    fi
done

section "Repository alerting sanity"

DUPLICATE_UIDS="$(
    grep -RhoE \
        '^[[:space:]]+- uid: [^[:space:]]+' \
        "$GRAFANA_ALERTING" \
        --include='*.yml' \
        --include='*.yaml' \
        2>/dev/null \
    | awk '{print $3}' \
    | sort \
    | uniq -d
)"

if [[ -z "$DUPLICATE_UIDS" ]]; then
    ok "Grafana provisioning UIDs unique"
else
    bad "Duplicate Grafana UIDs found:"
    echo "$DUPLICATE_UIDS"
fi

BAD_DATASOURCES="$(
    grep -RhoE \
        'datasourceUid:[[:space:]]+[^[:space:]]+' \
        "$GRAFANA_ALERTING" \
        --include='*.yml' \
        --include='*.yaml' \
        2>/dev/null \
    | awk '{print $2}' \
    | grep -Ev '^(prometheus|__expr__)$' \
    | sort -u || true
)"

if [[ -z "$BAD_DATASOURCES" ]]; then
    ok "Grafana rules use known datasource UIDs"
else
    bad "Unexpected datasource UID(s) found:"
    echo "$BAD_DATASOURCES"
fi

DUPLICATE_BASENAMES="$(
    find "$GRAFANA_ALERTING" \
        -type f \
        \( -name '*.yml' -o -name '*.yaml' \) \
        -printf '%f\n' \
    | sort \
    | uniq -d
)"

if [[ -z "$DUPLICATE_BASENAMES" ]]; then
    ok "Alert provisioning filenames unique"
else
    bad "Duplicate alert provisioning filenames:"
    echo "$DUPLICATE_BASENAMES"
fi

section "Git-to-runtime drift"

verify_sync \
    "$PROM_CONFIG" \
    "/etc/prometheus/prometheus.yml" \
    "Prometheus config"

verify_sync \
    "$PROM_OVERRIDE" \
    "/etc/systemd/system/prometheus.service.d/override.conf" \
    "Prometheus systemd override"

verify_sync \
    "$GRAFANA_DATASOURCE" \
    "/etc/grafana/provisioning/datasources/prometheus.yml" \
    "Grafana datasource"

verify_sync \
    "$GRAFANA_PROVIDER" \
    "/etc/grafana/provisioning/dashboards/homelab.yml" \
    "Grafana dashboard provider"

verify_sync \
    "$NTFY_CONFIG" \
    "/etc/ntfy/server.yml" \
    "ntfy configuration"
    
verify_host_sync \
    "$NODE_EXPORTER_ENV" \
    "/etc/default/prometheus-node-exporter" \
    "Node Exporter configuration"

while IFS= read -r -d '' dashboard; do
    filename="$(basename "$dashboard")"

    verify_sync \
        "$dashboard" \
        "/var/lib/grafana/dashboards/$filename" \
        "Grafana dashboard $filename"

done < <(
    find "$GRAFANA_DASHBOARDS" \
        -type f \
        -name '*.json' \
        -print0
)

while IFS= read -r -d '' alert_file; do
    filename="$(basename "$alert_file")"

    verify_sync \
        "$alert_file" \
        "/etc/grafana/provisioning/alerting/$filename" \
        "Grafana alerting $filename"

done < <(
    find "$GRAFANA_ALERTING" \
        -type f \
        \( -name '*.yml' -o -name '*.yaml' \) \
        -print0
)

if [[ "${1:-}" == "--notify" ]]; then

    section "Synthetic notification"

    MESSAGE="Homelab verify test $(date -Iseconds)"

    if remote "
        curl --fail --silent \
          -H 'Title: Homelab Verification' \
          -H 'Priority: default' \
          -H 'Tags: white_check_mark,test_tube' \
          -d '$MESSAGE' \
          http://127.0.0.1/homelab-alerts
    " >/dev/null; then
        ok "Synthetic ntfy message published"
    else
        bad "Synthetic ntfy publication failed"
    fi

fi

echo
echo "========================================"

if (( FAILURES == 0 )); then
    printf '\033[1;32m Homelab verification successful ✅\033[0m\n'
    echo "========================================"
    exit 0
else
    printf '\033[1;31m Homelab verification FAILED ❌\033[0m\n'
    printf ' %d check(s) failed\n' "$FAILURES"
    echo "========================================"
    exit 1
fi
