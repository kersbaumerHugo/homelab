#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
CT_ID="${CT_ID:-100}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROM_CONFIG="$REPO_ROOT/monitoring/prometheus/prometheus.yml"
PROM_OVERRIDE="$REPO_ROOT/monitoring/prometheus/systemd/override.conf"

GRAFANA_DATASOURCE="$REPO_ROOT/monitoring/grafana/provisioning/datasources/prometheus.yml"
GRAFANA_PROVIDER="$REPO_ROOT/monitoring/grafana/provisioning/dashboards/homelab.yml"
GRAFANA_DASHBOARDS="$REPO_ROOT/monitoring/grafana/dashboards"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_TMP="/tmp/homelab-deploy-$TIMESTAMP"
BACKUP_DIR="/root/homelab-config-backups/$TIMESTAMP"

info() {
    printf '\n\033[1;34m==>\033[0m %s\n' "$1"
}

ok() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$1"
}

fail() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2
    exit 1
}

remote() {
    ssh "$PVE_HOST" "pct exec $CT_ID -- bash -lc $(printf '%q' "$1")"
}

push_file() {
    local source="$1"
    local destination="$2"

    cat "$source" | ssh "$PVE_HOST" \
        "pct exec $CT_ID -- tee '$destination' >/dev/null"
}

required_files=(
    "$PROM_CONFIG"
    "$PROM_OVERRIDE"
    "$GRAFANA_DATASOURCE"
    "$GRAFANA_PROVIDER"
)

info "Validating local repository files"

for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || fail "Missing required file: $file"
done

python3 -m json.tool \
    "$GRAFANA_DASHBOARDS/pve01.json" >/dev/null \
    || fail "Invalid Grafana dashboard JSON"

ok "Local files validated"

info "Checking access to $PVE_HOST"

ssh -o BatchMode=yes "$PVE_HOST" true \
    || fail "Cannot access $PVE_HOST using SSH key"

ok "SSH access working"

info "Checking LXC $CT_ID"

CT_STATUS="$(ssh "$PVE_HOST" "pct status $CT_ID")"

echo "$CT_STATUS"

grep -q "status: running" <<< "$CT_STATUS" \
    || fail "CT $CT_ID is not running"

ok "Monitoring container is running"

info "Preparing temporary and backup directories"

remote "
mkdir -p '$REMOTE_TMP'
mkdir -p '$BACKUP_DIR'

mkdir -p /etc/prometheus
mkdir -p /etc/systemd/system/prometheus.service.d
mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /var/lib/grafana/dashboards
"

ok "Directories ready"

info "Uploading candidate configuration"

push_file "$PROM_CONFIG" \
    "$REMOTE_TMP/prometheus.yml"

push_file "$PROM_OVERRIDE" \
    "$REMOTE_TMP/prometheus-override.conf"

push_file "$GRAFANA_DATASOURCE" \
    "$REMOTE_TMP/grafana-prometheus.yml"

push_file "$GRAFANA_PROVIDER" \
    "$REMOTE_TMP/grafana-homelab.yml"

for dashboard in "$GRAFANA_DASHBOARDS"/*.json; do
    [[ -e "$dashboard" ]] || continue

    filename="$(basename "$dashboard")"

    push_file "$dashboard" \
        "$REMOTE_TMP/$filename"
done

ok "Candidate configuration uploaded"

info "Validating Prometheus configuration"

remote "
promtool check config '$REMOTE_TMP/prometheus.yml'
"

ok "Prometheus configuration valid"

info "Backing up currently deployed configuration"

remote "
cp -a /etc/prometheus/prometheus.yml \
    '$BACKUP_DIR/prometheus.yml' 2>/dev/null || true

cp -a /etc/systemd/system/prometheus.service.d/override.conf \
    '$BACKUP_DIR/prometheus-override.conf' 2>/dev/null || true

cp -a /etc/grafana/provisioning/datasources/prometheus.yml \
    '$BACKUP_DIR/grafana-prometheus.yml' 2>/dev/null || true

cp -a /etc/grafana/provisioning/dashboards/homelab.yml \
    '$BACKUP_DIR/grafana-homelab.yml' 2>/dev/null || true

cp -a /var/lib/grafana/dashboards \
    '$BACKUP_DIR/grafana-dashboards' 2>/dev/null || true
"

ok "Backup created at $BACKUP_DIR"

info "Deploying Prometheus"

remote "
install -o root -g root -m 0644 \
    '$REMOTE_TMP/prometheus.yml' \
    /etc/prometheus/prometheus.yml

install -o root -g root -m 0644 \
    '$REMOTE_TMP/prometheus-override.conf' \
    /etc/systemd/system/prometheus.service.d/override.conf
"

ok "Prometheus files deployed"

info "Deploying Grafana provisioning"

remote "
install -o root -g grafana -m 0644 \
    '$REMOTE_TMP/grafana-prometheus.yml' \
    /etc/grafana/provisioning/datasources/prometheus.yml

install -o root -g grafana -m 0644 \
    '$REMOTE_TMP/grafana-homelab.yml' \
    /etc/grafana/provisioning/dashboards/homelab.yml
"

for dashboard in "$GRAFANA_DASHBOARDS"/*.json; do
    [[ -e "$dashboard" ]] || continue

    filename="$(basename "$dashboard")"

    remote "
    install -o grafana -g grafana -m 0644 \
        '$REMOTE_TMP/$filename' \
        '/var/lib/grafana/dashboards/$filename'
    "
done

ok "Grafana files deployed"

info "Reloading services"

remote "
systemctl daemon-reload
systemctl restart prometheus
systemctl restart grafana-server
"

ok "Services restarted"

info "Running service health checks"

PROM_STATUS="$(remote "systemctl is-active prometheus")"
GRAFANA_STATUS="$(remote "systemctl is-active grafana-server")"

[[ "$PROM_STATUS" == "active" ]] \
    || fail "Prometheus is not active"

[[ "$GRAFANA_STATUS" == "active" ]] \
    || fail "Grafana is not active"

ok "Prometheus active"
ok "Grafana active"

info "Checking Prometheus health endpoint"

remote "
curl --fail --silent \
    http://127.0.0.1:9090/-/healthy
"

ok "Prometheus healthy"

info "Checking Grafana health endpoint"

remote "
curl --fail --silent \
    http://127.0.0.1:3000/api/health
"

ok "Grafana healthy"

info "Checking pve01 Prometheus target"

TARGET_HEALTH="$(remote "
curl -s http://127.0.0.1:9090/api/v1/targets \
| grep -o '192.168.10.10:9100[^}]*' \
| grep -o 'health\":\"[^\"]*' \
| head -1
")"

echo "$TARGET_HEALTH"

grep -q 'health":"up' <<< "$TARGET_HEALTH" \
    || fail "pve01 Prometheus target is not UP"

ok "pve01 target UP"

info "Cleaning temporary deployment files"

remote "
rm -rf '$REMOTE_TMP'
"

printf '\n'
printf '\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Monitoring deployment successful ✅\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
printf '\n'
printf 'Prometheus : http://192.168.10.162:9090\n'
printf 'Grafana    : http://192.168.10.162:3000\n'
printf 'Backup     : %s\n' "$BACKUP_DIR"
