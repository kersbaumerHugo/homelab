#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/monitoring/grafana/provisioning/alerting"

mkdir -p "$DIR"

write_alert() {
    if (( $# < 11 )); then
        echo "ERROR: write_alert requires at least 11 arguments, got $#" >&2
        exit 1
    fi

    local file="$1"
    local uid="$2"
    local title="$3"
    local expr="$4"
    local evaluator="$5"
    local threshold="$6"
    local hold="$7"
    local severity="$8"
    local nodata="$9"
    local summary="${10}"
    local description="${11}"
    local device="${12:-}"
    local folder
    local group

case "$file" in
    *collector-*)
        folder="Homelab - Monitoring"
        ;;

    *temperature-*)
        folder="Homelab - Temperature"
        ;;

    *)
        folder="Homelab - Storage"
        ;;
esac

group="$title"
    case "$nodata" in
        NoData|Alerting|OK|KeepLastState) ;;
        *)
            echo "ERROR: invalid noDataState '$nodata' for $file" >&2
            exit 1
            ;;
    esac

    local device_label=""
    if [[ -n "$device" ]]; then
        device_label="          device: $device"
    fi

    cat > "$DIR/$file" <<EOF
apiVersion: 1

groups:
  - orgId: 1
    name: $group
    folder: $folder
    interval: 1m

    rules:
      - uid: $uid
        title: $title
        condition: C

        data:
          - refId: A
            relativeTimeRange:
              from: 900
              to: 0
            datasourceUid: prometheus
            model:
              editorMode: code
              expr: |
                $expr
              instant: true
              intervalMs: 1000
              maxDataPoints: 43200
              refId: A

          - refId: C
            queryType: expression
            datasourceUid: __expr__
            model:
              conditions:
                - evaluator:
                    params:
                      - $threshold
                    type: $evaluator
                  operator:
                    type: and
                  query:
                    params:
                      - C
                  reducer:
                    params: []
                    type: last
                  type: query
              datasource:
                type: __expr__
                uid: __expr__
              expression: A
              intervalMs: 1000
              maxDataPoints: 43200
              refId: C
              type: threshold

        noDataState: $nodata
        execErrState: Error
        for: $hold
        keepFiringFor: 1m

        annotations:
          summary: $summary
          description: $description

        labels:
          category: smart
          host: pve01
          severity: $severity
$device_label

        isPaused: false

        notification_settings:
          receiver: ntfy-homelab
EOF
}
write_alert \
  "homelab-pve01-smart-collector-failed.yml" \
  "pve01smartcolf" \
  "pve01 - SMART collector failed" \
  'homelab_smart_collector_success{instance="192.168.10.10:9100"}' \
  lt 1 2m critical Alerting \
  "SMART collector failed on pve01" \
  "The SMART collector is reporting an unsuccessful execution."

write_alert \
  "homelab-pve01-smart-collector-stale.yml" \
  "pve01smartstale" \
  "pve01 - SMART collector metrics stale" \
  'time() - homelab_smart_collector_last_run_unixtime{instance="192.168.10.10:9100"}' \
  gt 900 2m critical Alerting \
  "SMART metrics are stale on pve01" \
  "The SMART collector has not produced fresh metrics for more than 15 minutes."

write_alert \
  "homelab-pve01-smart-hdd-health.yml" \
  "pve01smarthddh" \
  "pve01 - HDD SMART health failed" \
  'homelab_smart_device_health{instance="192.168.10.10:9100",device="hdd-backup"}' \
  lt 1 1m critical NoData \
  "Backup HDD SMART health failed" \
  "The backup HDD is reporting a failing SMART overall-health status." \
  hdd-backup

write_alert \
  "homelab-pve01-smart-ssd-health.yml" \
  "pve01smartssdh" \
  "pve01 - SSD SMART health failed" \
  'homelab_smart_device_health{instance="192.168.10.10:9100",device="pve-ssd"}' \
  lt 1 1m critical NoData \
  "Proxmox SSD SMART health failed" \
  "The Proxmox SSD is reporting a failing SMART overall-health status." \
  pve-ssd

write_alert \
  "homelab-pve01-smart-hdd-pending.yml" \
  "pve01smarthddpend" \
  "pve01 - HDD pending sectors" \
  'homelab_smart_pending_sectors{instance="192.168.10.10:9100",device="hdd-backup"}' \
  gt 0 1m critical NoData \
  "Backup HDD has pending sectors" \
  "One or more sectors are waiting to be remapped on the backup HDD." \
  hdd-backup

write_alert \
  "homelab-pve01-smart-hdd-uncorrectable.yml" \
  "pve01smarthddoff" \
  "pve01 - HDD offline uncorrectable sectors" \
  'homelab_smart_offline_uncorrectable{instance="192.168.10.10:9100",device="hdd-backup"}' \
  gt 0 1m critical NoData \
  "Backup HDD has offline uncorrectable sectors" \
  "SMART detected sectors that could not be corrected during offline testing." \
  hdd-backup

write_alert \
  "homelab-pve01-smart-hdd-temperature-warning.yml" \
  "pve01smarthddtw" \
  "pve01 - HDD temperature warning" \
  'homelab_smart_temperature_celsius{instance="192.168.10.10:9100",device="hdd-backup"}' \
  gt 50 10m warning NoData \
  "Backup HDD temperature high" \
  "Backup HDD temperature has remained above 50 degrees Celsius for 10 minutes." \
  hdd-backup

write_alert \
  "homelab-pve01-smart-hdd-temperature-critical.yml" \
  "pve01smarthddtc" \
  "pve01 - HDD temperature critical" \
  'homelab_smart_temperature_celsius{instance="192.168.10.10:9100",device="hdd-backup"}' \
  gt 60 5m critical NoData \
  "Backup HDD temperature critical" \
  "Backup HDD temperature has remained above 60 degrees Celsius for 5 minutes." \
  hdd-backup

write_alert \
  "homelab-pve01-smart-ssd-temperature-warning.yml" \
  "pve01smartssdtw" \
  "pve01 - SSD temperature warning" \
  'homelab_smart_temperature_celsius{instance="192.168.10.10:9100",device="pve-ssd"}' \
  gt 60 10m warning NoData \
  "Proxmox SSD temperature high" \
  "Proxmox SSD temperature has remained above 60 degrees Celsius for 10 minutes." \
  pve-ssd

write_alert \
  "homelab-pve01-smart-ssd-temperature-critical.yml" \
  "pve01smartssdtc" \
  "pve01 - SSD temperature critical" \
  'homelab_smart_temperature_celsius{instance="192.168.10.10:9100",device="pve-ssd"}' \
  gt 70 5m critical NoData \
  "Proxmox SSD temperature critical" \
  "Proxmox SSD temperature has remained above 70 degrees Celsius for 5 minutes." \
  pve-ssd

write_alert \
  "homelab-pve01-smart-reallocated-change.yml" \
  "pve01smartrealloc" \
  "pve01 - SMART reallocated sectors increased" \
  'changes(homelab_smart_reallocated_sectors{instance="192.168.10.10:9100"}[24h])' \
  gt 0 1m warning NoData \
  "SMART reallocated-sector counter changed" \
  "A disk reported a new change in its reallocated-sector counter during the last 24 hours."

write_alert \
  "homelab-pve01-smart-uncorrectable-change.yml" \
  "pve01smartuncnew" \
  "pve01 - SMART reported uncorrectable increased" \
  'changes(homelab_smart_reported_uncorrectable{instance="192.168.10.10:9100"}[24h])' \
  gt 0 1m critical NoData \
  "New SMART uncorrectable error detected" \
  "A disk reported a change in its uncorrectable-error counter during the last 24 hours."

write_alert \
  "homelab-pve01-smart-crc-change.yml" \
  "pve01smartcrcnew" \
  "pve01 - SMART CRC errors increased" \
  'changes(homelab_smart_crc_errors{instance="192.168.10.10:9100"}[24h])' \
  gt 0 1m warning NoData \
  "New SMART CRC error detected" \
  "A disk reported a change in its interface CRC-error counter during the last 24 hours."

echo "SMART alert files generated successfully ✅"
