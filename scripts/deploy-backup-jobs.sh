#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE_HOST="${PVE_HOST:-pve01}"
JOB="${1:-mon01-daily}"

case "$JOB" in
    mon01-daily|ha01-daily) ;;
    *)
        echo "[ERROR] Unsupported backup job: $JOB" >&2
        exit 1
        ;;
esac

CONFIG="$ROOT/proxmox/pve01/backup-jobs/${JOB}.yml"

remote() {
    local cmd
    printf -v cmd '%q ' "$@"
    printf '%s\n' "$cmd" | ssh -T "$PVE_HOST" 'bash -se'
}

[[ -f "$CONFIG" ]] || {
    echo "[ERROR] Missing $CONFIG"
    exit 1
}

read -r JOB_ID VMID STORAGE MODE COMPRESS SCHEDULE DAILY WEEKLY MONTHLY < <(
    python3 - "$CONFIG" <<'PY'
import sys
import yaml

d = yaml.safe_load(open(sys.argv[1]))

print(
    d["id"],
    d["target"]["vmid"],
    d["backup"]["storage"],
    d["backup"]["mode"],
    d["backup"]["compression"],
    d["backup"]["schedule"],
    d["retention"]["keep_daily"],
    d["retention"]["keep_weekly"],
    d["retention"]["keep_monthly"],
)
PY
)

PRUNE="keep-daily=$DAILY,keep-weekly=$WEEKLY,keep-monthly=$MONTHLY"

echo "==> Checking pve01"

remote true >/dev/null
echo "[OK] pve01 reachable"

echo "==> Applying backup job: $JOB_ID"

if remote pvesh get "/cluster/backup/$JOB_ID" \
    --output-format json >/dev/null 2>&1
then
    echo "Existing job found; updating"

    remote pvesh set "/cluster/backup/$JOB_ID" \
        --storage "$STORAGE" \
        --vmid "$VMID" \
        --mode "$MODE" \
        --compress "$COMPRESS" \
        --schedule "$SCHEDULE" \
        --prune-backups "$PRUNE" \
        --enabled 1
else
    echo "Job does not exist; creating"

    remote pvesh create /cluster/backup \
        --id "$JOB_ID" \
        --storage "$STORAGE" \
        --vmid "$VMID" \
        --mode "$MODE" \
        --compress "$COMPRESS" \
        --schedule "$SCHEDULE" \
        --prune-backups "$PRUNE" \
        --enabled 1
fi

echo
echo "==> Runtime state"

remote pvesh get "/cluster/backup/$JOB_ID" \
    --output-format yaml

echo
echo "Backup job deployment successful ✅"
