#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/monitoring/grafana/provisioning/alerting"

emit_rule() {
    local file="$1"
    local uid="$2"
    local title="$3"
    local folder="$4"
    local expr="$5"
    local evaluator="$6"
    local threshold="$7"
    local duration="$8"
    local severity="$9"
    local summary="${10}"
    local description="${11}"

    case "$evaluator" in
        lt|gt) ;;
        *)
            echo "Invalid evaluator: $evaluator" >&2
            exit 1
            ;;
    esac

    cat > "$OUT/$file" <<EOF
apiVersion: 1

groups:
  - orgId: 1
    name: $title
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

        noDataState: Alerting
        execErrState: Error
        for: $duration
        keepFiringFor: 1m

        annotations:
          summary: $summary
          description: $description

        labels:
          category: backup
          host: pve01
          severity: $severity

        isPaused: false

        notification_settings:
          receiver: ntfy-homelab
EOF
}

emit_rule \
    "homelab-pve01-backup-collector-failed.yml" \
    "pve01bkcolfail" \
    "pve01 - Backup collector failed" \
    "Homelab - Monitoring" \
    'homelab_backup_collector_success{instance="192.168.10.10:9100"}' \
    "lt" \
    "1" \
    "2m" \
    "critical" \
    "Backup collector failed on pve01" \
    "The backup metrics collector is reporting an unsuccessful execution."

emit_rule \
    "homelab-pve01-backup-collector-stale.yml" \
    "pve01bkcolstale" \
    "pve01 - Backup collector metrics stale" \
    "Homelab - Monitoring" \
    'time() - homelab_backup_collector_last_run_unixtime{instance="192.168.10.10:9100"}' \
    "gt" \
    "900" \
    "2m" \
    "critical" \
    "Backup collector metrics are stale on pve01" \
    "The backup collector has not produced fresh metrics for more than 15 minutes."

emit_rule \
    "homelab-pve01-backup-job-missing.yml" \
    "pve01bkjobmissing" \
    "pve01 - mon01 backup job missing" \
    "Homelab - Storage" \
    'homelab_backup_job_exists{instance="192.168.10.10:9100",backup_job="mon01-daily",vmid="100"}' \
    "lt" \
    "1" \
    "2m" \
    "critical" \
    "mon01 backup job is missing" \
    "The mon01-daily backup job is no longer present on pve01."

emit_rule \
    "homelab-pve01-backup-job-disabled.yml" \
    "pve01bkjobdisabled" \
    "pve01 - mon01 backup job disabled" \
    "Homelab - Storage" \
    'homelab_backup_job_enabled{instance="192.168.10.10:9100",backup_job="mon01-daily",vmid="100"}' \
    "lt" \
    "1" \
    "2m" \
    "critical" \
    "mon01 backup job is disabled" \
    "The mon01-daily backup job exists but is disabled."

emit_rule \
    "homelab-pve01-backup-artifact-missing.yml" \
    "pve01bkartifact" \
    "pve01 - mon01 backup artifact missing" \
    "Homelab - Storage" \
    'homelab_backup_artifact_present{instance="192.168.10.10:9100",backup_job="mon01-daily",vmid="100"}' \
    "lt" \
    "1" \
    "2m" \
    "critical" \
    "No mon01 backup artifact found" \
    "No readable mon01 vzdump backup artifact was discovered on hdd-backup."

emit_rule \
    "homelab-pve01-backup-stale.yml" \
    "pve01bkstale" \
    "pve01 - mon01 backup stale" \
    "Homelab - Storage" \
    'time() - homelab_backup_last_success_unixtime{instance="192.168.10.10:9100",backup_job="mon01-daily",vmid="100"}' \
    "gt" \
    "93600" \
    "10m" \
    "critical" \
    "mon01 backup is older than 26 hours" \
    "The latest mon01 backup artifact has exceeded the 26 hour freshness objective."

echo "Backup alert rules generated ✅"
