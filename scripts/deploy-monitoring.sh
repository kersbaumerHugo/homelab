#!/usr/bin/env bash
# Remote commands intentionally expand selected variables on the SSH client.
# shellcheck disable=SC2029
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
CT_ID="${CT_ID:-100}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NODE_EXPORTER_ENV="$REPO_ROOT/monitoring/node-exporter/pve01.env"

LVM_COLLECTOR="$REPO_ROOT/monitoring/node-exporter/lvm-collector.sh"
LVM_SERVICE="$REPO_ROOT/monitoring/node-exporter/systemd/homelab-lvm-collector.service"
LVM_TIMER="$REPO_ROOT/monitoring/node-exporter/systemd/homelab-lvm-collector.timer"

SMART_COLLECTOR="$REPO_ROOT/monitoring/node-exporter/smart-collector.py"
SMART_SERVICE="$REPO_ROOT/monitoring/node-exporter/systemd/homelab-smart-collector.service"
SMART_TIMER="$REPO_ROOT/monitoring/node-exporter/systemd/homelab-smart-collector.timer"

VALIDATOR="$REPO_ROOT/scripts/validate-monitoring.sh"

PROM_CONFIG="$REPO_ROOT/monitoring/prometheus/prometheus.yml"
PROM_OVERRIDE="$REPO_ROOT/monitoring/prometheus/systemd/override.conf"

GRAFANA_DATASOURCE="$REPO_ROOT/monitoring/grafana/provisioning/datasources/prometheus.yml"
GRAFANA_PROVIDER="$REPO_ROOT/monitoring/grafana/provisioning/dashboards/homelab.yml"
GRAFANA_DASHBOARDS="$REPO_ROOT/monitoring/grafana/dashboards"
GRAFANA_ALERTING="$REPO_ROOT/monitoring/grafana/provisioning/alerting"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_TMP="/tmp/homelab-deploy-$TIMESTAMP"
BACKUP_DIR="/root/homelab-config-backups/$TIMESTAMP"

HOST_REMOTE_TMP="/tmp/homelab-host-deploy-$TIMESTAMP"
HOST_BACKUP_DIR="/root/homelab-host-config-backups/$TIMESTAMP"

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


DEPLOY_STARTED=false
ROLLING_BACK=false
# Called indirectly by the EXIT trap.
# shellcheck disable=SC2329
rollback() {
    [[ "$DEPLOY_STARTED" == "true" ]] || return 0
    [[ "$ROLLING_BACK" == "false" ]] || return 0

    ROLLING_BACK=true

    printf '\n\033[1;33m==> Rolling back monitoring deployment\033[0m\n'
## node exporter e lvm exporter
ssh "$PVE_HOST" "
systemctl disable --now homelab-lvm-collector.timer \
    2>/dev/null || true

if [[ -f '$HOST_BACKUP_DIR/lvm-collector.existed' ]]; then
    cp -a '$HOST_BACKUP_DIR/homelab-lvm-collector' \
        /usr/local/sbin/homelab-lvm-collector
else
    rm -f /usr/local/sbin/homelab-lvm-collector
fi

if [[ -f '$HOST_BACKUP_DIR/lvm-service.existed' ]]; then
    cp -a '$HOST_BACKUP_DIR/homelab-lvm-collector.service' \
        /etc/systemd/system/homelab-lvm-collector.service
else
    rm -f /etc/systemd/system/homelab-lvm-collector.service
fi

if [[ -f '$HOST_BACKUP_DIR/lvm-timer.existed' ]]; then
    cp -a '$HOST_BACKUP_DIR/homelab-lvm-collector.timer' \
        /etc/systemd/system/homelab-lvm-collector.timer
else
    rm -f /etc/systemd/system/homelab-lvm-collector.timer
fi

if [[ -f '$HOST_BACKUP_DIR/lvm-prom.existed' ]]; then
    cp -a '$HOST_BACKUP_DIR/homelab_lvm.prom' \
        /var/lib/prometheus/node-exporter/homelab_lvm.prom
else
    rm -f /var/lib/prometheus/node-exporter/homelab_lvm.prom
fi

systemctl daemon-reload

if [[ -f '$HOST_BACKUP_DIR/lvm-timer.enabled' ]]; then
    systemctl enable --now homelab-lvm-collector.timer || true
fi

systemctl reset-failed homelab-lvm-collector.service \
    2>/dev/null || true
"
### ---------------------------------------------------------
    remote "
    if [[ -f '$BACKUP_DIR/prometheus.yml' ]]; then
        cp -a '$BACKUP_DIR/prometheus.yml' \
            /etc/prometheus/prometheus.yml
    fi

    if [[ -f '$BACKUP_DIR/prometheus-override.conf' ]]; then
        cp -a '$BACKUP_DIR/prometheus-override.conf' \
            /etc/systemd/system/prometheus.service.d/override.conf
    fi

    if [[ -f '$BACKUP_DIR/grafana-prometheus.yml' ]]; then
        cp -a '$BACKUP_DIR/grafana-prometheus.yml' \
            /etc/grafana/provisioning/datasources/prometheus.yml
    fi

    if [[ -f '$BACKUP_DIR/grafana-homelab.yml' ]]; then
        cp -a '$BACKUP_DIR/grafana-homelab.yml' \
            /etc/grafana/provisioning/dashboards/homelab.yml
    fi

    if [[ -d '$BACKUP_DIR/grafana-dashboards' ]]; then
        rm -rf /var/lib/grafana/dashboards
        cp -a '$BACKUP_DIR/grafana-dashboards' \
            /var/lib/grafana/dashboards
    fi

    if [[ -d '$BACKUP_DIR/grafana-alerting' ]]; then
        rm -rf /etc/grafana/provisioning/alerting
        cp -a '$BACKUP_DIR/grafana-alerting' \
            /etc/grafana/provisioning/alerting
    fi

    systemctl daemon-reload
    systemctl restart prometheus || true
    systemctl restart grafana-server || true
    "

    printf '\033[1;33m[ROLLBACK]\033[0m Previous configuration restored\n'
}

remote() {
    ssh "$PVE_HOST" "pct exec $CT_ID -- bash -lc $(printf '%q' "$1")"
}

push_file() {
    local source="$1"
    local destination="$2"

    ssh "$PVE_HOST" \
    "pct exec $CT_ID -- tee '$destination' >/dev/null" \
    < "$source"
}

wait_for_health() {
    local name="$1"
    local url="$2"

    for attempt in {1..12}; do
        if remote "curl --fail --silent '$url'" >/dev/null 2>&1; then
            ok "$name healthy"
            return 0
        fi

        echo "Waiting for $name... ($attempt/12)"
        sleep 5
    done

    printf '\033[1;31m[ERROR]\033[0m %s did not become healthy\n' "$name" >&2
    return 1
}

push_host_file() {
    local source="$1"
    local destination="$2"

    ssh "$PVE_HOST" \
        "tee '$destination' >/dev/null" \
        < "$source"
}

# Called indirectly by the EXIT trap.
# shellcheck disable=SC2329
on_exit() {
    local exit_code="$1"

    # Successful exit: nothing to recover.
    if (( exit_code == 0 )); then
        return 0
    fi

    if [[ "$DEPLOY_STARTED" == "true" ]]; then
        rollback || true
    fi

    remote "rm -rf '$REMOTE_TMP'" >/dev/null 2>&1 || true
}

trap 'on_exit $?' EXIT

required_files=(
    "$PROM_CONFIG"
    "$PROM_OVERRIDE"
    "$GRAFANA_DATASOURCE"
    "$GRAFANA_PROVIDER"
    "$NODE_EXPORTER_ENV"
    "$LVM_COLLECTOR"
    "$LVM_SERVICE"
    "$LVM_TIMER"
    "$SMART_COLLECTOR"
    "$SMART_SERVICE"
    "$SMART_TIMER"
)

info "Running pre-deployment validation"

[[ -x "$VALIDATOR" ]] \
    || fail "Validator not found or not executable: $VALIDATOR"

"$VALIDATOR"

ok "Repository validation passed"

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

ssh "$PVE_HOST" "
mkdir -p '$HOST_REMOTE_TMP'
mkdir -p '$HOST_BACKUP_DIR'
"

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

#Node Exporter
push_host_file \
    "$NODE_EXPORTER_ENV" \
    "$HOST_REMOTE_TMP/prometheus-node-exporter"
    
#LVM
push_host_file \
    "$LVM_COLLECTOR" \
    "$HOST_REMOTE_TMP/homelab-lvm-collector"

push_host_file \
    "$LVM_SERVICE" \
    "$HOST_REMOTE_TMP/homelab-lvm-collector.service"

push_host_file \
    "$LVM_TIMER" \
    "$HOST_REMOTE_TMP/homelab-lvm-collector.timer"

#Smart
push_host_file \
    "$SMART_COLLECTOR" \
    "$HOST_REMOTE_TMP/homelab-smart-collector"

push_host_file \
    "$SMART_SERVICE" \
    "$HOST_REMOTE_TMP/homelab-smart-collector.service"

push_host_file \
    "$SMART_TIMER" \
    "$HOST_REMOTE_TMP/homelab-smart-collector.timer"


for dashboard in "$GRAFANA_DASHBOARDS"/*.json; do
    [[ -e "$dashboard" ]] || continue

    filename="$(basename "$dashboard")"

    push_file "$dashboard" \
        "$REMOTE_TMP/$filename"
done

while IFS= read -r -d '' alert_file; do
    filename="$(basename "$alert_file")"

    push_file "$alert_file" \
        "$REMOTE_TMP/$filename"
done < <(
    find "$GRAFANA_ALERTING" \
        -type f \
        \( -name '*.yml' -o -name '*.yaml' \) \
        -print0
)

ssh "$PVE_HOST" \
    "bash -n '$HOST_REMOTE_TMP/prometheus-node-exporter'"

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
    
cp -a /etc/grafana/provisioning/alerting \
    '$BACKUP_DIR/grafana-alerting' 2>/dev/null || true
    
"

ok "Backup created at $BACKUP_DIR"


ssh "$PVE_HOST" "
if [[ -e /usr/local/sbin/homelab-lvm-collector ]]; then
    touch '$HOST_BACKUP_DIR/lvm-collector.existed'
    cp -a /usr/local/sbin/homelab-lvm-collector \
        '$HOST_BACKUP_DIR/homelab-lvm-collector'
fi

if [[ -e /etc/systemd/system/homelab-lvm-collector.service ]]; then
    touch '$HOST_BACKUP_DIR/lvm-service.existed'
    cp -a /etc/systemd/system/homelab-lvm-collector.service \
        '$HOST_BACKUP_DIR/homelab-lvm-collector.service'
fi

if [[ -e /etc/systemd/system/homelab-lvm-collector.timer ]]; then
    touch '$HOST_BACKUP_DIR/lvm-timer.existed'
    cp -a /etc/systemd/system/homelab-lvm-collector.timer \
        '$HOST_BACKUP_DIR/homelab-lvm-collector.timer'
fi

if [[ -e /var/lib/prometheus/node-exporter/homelab_lvm.prom ]]; then
    touch '$HOST_BACKUP_DIR/lvm-prom.existed'
    cp -a /var/lib/prometheus/node-exporter/homelab_lvm.prom \
        '$HOST_BACKUP_DIR/homelab_lvm.prom'
fi

if systemctl is-enabled --quiet homelab-lvm-collector.timer 2>/dev/null; then
    touch '$HOST_BACKUP_DIR/lvm-timer.enabled'
fi
"

#SMART
ssh "$PVE_HOST" "
if [[ -e /usr/local/sbin/homelab-smart-collector ]]; then
    touch '$HOST_BACKUP_DIR/smart-collector.existed'
    cp -a /usr/local/sbin/homelab-smart-collector \
        '$HOST_BACKUP_DIR/homelab-smart-collector'
fi

if [[ -e /etc/systemd/system/homelab-smart-collector.service ]]; then
    touch '$HOST_BACKUP_DIR/smart-service.existed'
    cp -a /etc/systemd/system/homelab-smart-collector.service \
        '$HOST_BACKUP_DIR/homelab-smart-collector.service'
fi

if [[ -e /etc/systemd/system/homelab-smart-collector.timer ]]; then
    touch '$HOST_BACKUP_DIR/smart-timer.existed'
    cp -a /etc/systemd/system/homelab-smart-collector.timer \
        '$HOST_BACKUP_DIR/homelab-smart-collector.timer'
fi

if [[ -e /var/lib/prometheus/node-exporter/homelab_smart.prom ]]; then
    touch '$HOST_BACKUP_DIR/smart-prom.existed'
    cp -a /var/lib/prometheus/node-exporter/homelab_smart.prom \
        '$HOST_BACKUP_DIR/homelab_smart.prom'
fi

if systemctl is-enabled --quiet homelab-smart-collector.timer 2>/dev/null; then
    touch '$HOST_BACKUP_DIR/smart-timer.enabled'
fi
"


DEPLOY_STARTED=true

info "Deploying Node Exporter configuration"

ssh "$PVE_HOST" "
install -o root -g root -m 0644 \
    '$HOST_REMOTE_TMP/prometheus-node-exporter' \
    /etc/default/prometheus-node-exporter

systemctl restart prometheus-node-exporter
"

ok "Node Exporter configuration deployed"

info "Deploying LVM collector"

ssh "$PVE_HOST" "
install -o root -g root -m 0755 \
    '$HOST_REMOTE_TMP/homelab-lvm-collector' \
    /usr/local/sbin/homelab-lvm-collector

install -o root -g root -m 0644 \
    '$HOST_REMOTE_TMP/homelab-lvm-collector.service' \
    /etc/systemd/system/homelab-lvm-collector.service

install -o root -g root -m 0644 \
    '$HOST_REMOTE_TMP/homelab-lvm-collector.timer' \
    /etc/systemd/system/homelab-lvm-collector.timer

systemctl daemon-reload

systemctl enable --now homelab-lvm-collector.timer

systemctl start homelab-lvm-collector.service
"

ok "LVM collector deployed"

info "Deploying SMART collector"

ssh "$PVE_HOST" "
install -o root -g root -m 0755 \
    '$HOST_REMOTE_TMP/homelab-smart-collector' \
    /usr/local/sbin/homelab-smart-collector

install -o root -g root -m 0644 \
    '$HOST_REMOTE_TMP/homelab-smart-collector.service' \
    /etc/systemd/system/homelab-smart-collector.service

install -o root -g root -m 0644 \
    '$HOST_REMOTE_TMP/homelab-smart-collector.timer' \
    /etc/systemd/system/homelab-smart-collector.timer

systemctl daemon-reload
systemctl enable --now homelab-smart-collector.timer
systemctl start homelab-smart-collector.service
"

ok "SMART collector deployed"


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

info "Synchronizing Grafana alerting provisioning"

remote "
find /etc/grafana/provisioning/alerting \
  -maxdepth 1 \
  -type f \
  -name 'homelab-*.yml' \
  -delete
"

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

for alert_file in "$GRAFANA_ALERTING"/*.yml; do
    [[ -e "$alert_file" ]] || continue

    filename="$(basename "$alert_file")"

    remote "
    install -o root -g grafana -m 0644 \
        '$REMOTE_TMP/$filename' \
        '/etc/grafana/provisioning/alerting/$filename'
    "
done

ok "Grafana files deployed"


info "Checking Node Exporter filesystem metrics"

NODE_EXPORTER_READY=false

for attempt in {1..12}; do
    if ssh "$PVE_HOST" \
        "curl --fail --silent http://127.0.0.1:9100/metrics \
        | grep -q 'mountpoint=\"/mnt/pve/hdd-backup\"'"; then

        NODE_EXPORTER_READY=true
        break
    fi

    echo "Waiting for Node Exporter... ($attempt/12)"
    sleep 5
done

[[ "$NODE_EXPORTER_READY" == "true" ]] \
    || fail "Node Exporter did not expose hdd-backup filesystem metrics"

ok "hdd-backup filesystem metric exposed"

SMART_TIMER_STATUS="$(
    ssh "$PVE_HOST" \
        "systemctl is-active homelab-smart-collector.timer" \
        2>/dev/null || true
)"

[[ "$SMART_TIMER_STATUS" == "active" ]] \
    || fail "SMART collector timer is not active"

SMART_METRICS="$(
    ssh "$PVE_HOST" \
        "curl -fsS http://127.0.0.1:9100/metrics \
        | grep '^homelab_smart_'" \
        2>/dev/null || true
)"

grep -q 'homelab_smart_collector_success 1' <<< "$SMART_METRICS" \
    || fail "SMART collector did not publish successful metrics"

ok "SMART collector timer active and metrics available"

info "Checking LVM collector"

LVM_TIMER_STATUS="$(
    ssh "$PVE_HOST" \
        "systemctl is-active homelab-lvm-collector.timer" \
        2>/dev/null || true
)"

[[ "$LVM_TIMER_STATUS" == "active" ]] \
    || fail "LVM collector timer is not active"

LVM_METRICS="$(
    ssh "$PVE_HOST" \
        "curl --fail --silent http://127.0.0.1:9100/metrics \
        | grep '^homelab_lvm_'" \
        2>/dev/null || true
)"

grep -q 'homelab_lvm_collector_success 1' <<< "$LVM_METRICS" \
    || fail "LVM collector did not publish successful metrics"

ok "LVM collector timer active and metrics available"

info "Reloading services"

remote "
systemctl daemon-reload
systemctl restart prometheus
systemctl restart grafana-server
"

ok "Services restarted"

if [[ "${HOMELAB_FAULT_INJECTION:-}" == "after-restart" ]]; then
    printf '\n\033[1;35m[CHAOS]\033[0m Injecting failure after service restart\n'
    exit 42
fi

info "Running service health checks"

PROM_STATUS="$(remote "systemctl is-active prometheus")"
GRAFANA_STATUS="$(remote "systemctl is-active grafana-server")"

[[ "$PROM_STATUS" == "active" ]] \
    || fail "Prometheus is not active"

[[ "$GRAFANA_STATUS" == "active" ]] \
    || fail "Grafana is not active"

ok "Prometheus active"
ok "Grafana active"

info "Checking application health"

wait_for_health \
    "Prometheus" \
    "http://127.0.0.1:9090/-/healthy"

wait_for_health \
    "Grafana" \
    "http://127.0.0.1:3000/api/health"

info "Checking pve01 Prometheus target"

TARGET_UP=false

for attempt in {1..12}; do
    TARGET_OUTPUT="$(remote \
        "promtool query instant http://127.0.0.1:9090 'up{job=\"pve01\"}'" \
        2>/dev/null || true)"

    if grep -q '=> 1' <<< "$TARGET_OUTPUT"; then
        TARGET_UP=true
        echo "$TARGET_OUTPUT"
        break
    fi

    echo "Waiting for Prometheus scrape... ($attempt/12)"
    sleep 5
done

[[ "$TARGET_UP" == "true" ]] \
    || fail "pve01 Prometheus target did not become UP within 60 seconds"

ok "pve01 target UP"

DEPLOY_STARTED=false
trap - EXIT

info "Cleaning temporary deployment files"

remote "
rm -rf '$REMOTE_TMP'
"
ssh "$PVE_HOST" "rm -rf '$HOST_REMOTE_TMP'"


printf '\n'
printf '\033[1;32m========================================\033[0m\n'
printf '\033[1;32m Monitoring deployment successful ✅\033[0m\n'
printf '\033[1;32m========================================\033[0m\n'
printf '\n'
printf 'Prometheus : http://192.168.10.162:9090\n'
printf 'Grafana    : http://192.168.10.162:3000\n'
printf 'Backup     : %s\n' "$BACKUP_DIR"
