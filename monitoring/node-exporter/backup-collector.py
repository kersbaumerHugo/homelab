#!/usr/bin/env python3

import glob
import json
import os
import subprocess
import time

JOB_ID = "mon01-daily"
VMID = "100"
BACKUP_PATTERN = "/mnt/pve/hdd-backup/dump/vzdump-lxc-100-*.tar.zst"
OUTPUT = "/var/lib/prometheus/node-exporter/homelab_backup.prom"


def metric(name, value, labels=""):
    if labels:
        return f'{name}{{{labels}}} {value}'
    return f"{name} {value}"


labels = f'backup_job="{JOB_ID}",vmid="{VMID}"'
lines = []
collector_success = 1

try:
    result = subprocess.run(
        [
            "pvesh",
            "get",
            f"/cluster/backup/{JOB_ID}",
            "--output-format",
            "json",
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=15,
    )

    if result.returncode == 0:
        job = json.loads(result.stdout)

        lines.append(
            metric(
                "homelab_backup_job_exists",
                1,
                labels,
            )
        )

        enabled = job.get("enabled", 0)

        if isinstance(enabled, str):
            enabled = 1 if enabled.lower() in (
                "1",
                "true",
                "yes",
                "on",
            ) else 0
        else:
            enabled = int(bool(enabled))

        lines.append(
            metric(
                "homelab_backup_job_enabled",
                enabled,
                labels,
            )
        )
    else:
        lines.append(
            metric(
                "homelab_backup_job_exists",
                0,
                labels,
            )
        )

        lines.append(
            metric(
                "homelab_backup_job_enabled",
                0,
                labels,
            )
        )

    backups = glob.glob(BACKUP_PATTERN)

    if backups:
        latest = max(
            backups,
            key=os.path.getmtime,
        )

        timestamp = int(os.path.getmtime(latest))
        size = os.path.getsize(latest)

        lines.append(
            metric(
                "homelab_backup_artifact_present",
                1,
                labels,
            )
        )

        lines.append(
            metric(
                "homelab_backup_last_success_unixtime",
                timestamp,
                labels,
            )
        )

        lines.append(
            metric(
                "homelab_backup_last_size_bytes",
                size,
                labels,
            )
        )
    else:
        lines.append(
            metric(
                "homelab_backup_artifact_present",
                0,
                labels,
            )
        )

except Exception:
    collector_success = 0

lines.append(
    metric(
        "homelab_backup_collector_success",
        collector_success,
    )
)

lines.append(
    metric(
        "homelab_backup_collector_last_run_unixtime",
        int(time.time()),
    )
)

tmp = OUTPUT + ".tmp"

with open(tmp, "w", encoding="utf-8") as file:
    file.write("\n".join(lines) + "\n")

os.chmod(tmp, 0o644)
os.replace(tmp, OUTPUT)
