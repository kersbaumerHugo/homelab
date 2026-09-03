#!/usr/bin/env python3

import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path


TEXTFILE_DIR = Path(
    os.environ.get(
        "TEXTFILE_DIR",
        "/var/lib/prometheus/node-exporter",
    )
)

OUTPUT = TEXTFILE_DIR / "homelab_smart.prom"

# Logical role -> expected hardware model.
DEVICES = {
    "hdd-backup": "ST1000DM010-2EP102",
    "pve-ssd": "P3-512",
}

ATA_ATTRIBUTES = {
    5: "reallocated_sectors",
    187: "reported_uncorrectable",
    197: "pending_sectors",
    198: "offline_uncorrectable",
    199: "crc_errors",
}


def run(command):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def escape_label(value):
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace('"', '\\"')
    )


def numeric(value):
    if isinstance(value, (int, float)):
        return value

    if isinstance(value, str):
        match = re.match(r"^-?\d+(?:\.\d+)?", value.strip())

        if match:
            return match.group(0)

    return None


def discover_devices():
    result = run(
        [
            "lsblk",
            "--json",
            "--nodeps",
            "--output",
            "PATH,MODEL,TYPE",
        ]
    )

    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())

    data = json.loads(result.stdout)

    discovered = {}

    for block in data.get("blockdevices", []):
        if block.get("type") != "disk":
            continue

        model = (block.get("model") or "").strip()
        path = block.get("path")

        if model and path:
            discovered[model] = path

    return discovered


def ata_attributes(data):
    values = {}

    table = (
        data.get("ata_smart_attributes", {})
        .get("table", [])
    )

    for attribute in table:
        attr_id = attribute.get("id")

        if attr_id not in ATA_ATTRIBUTES:
            continue

        value = numeric(
            attribute.get("raw", {}).get("value")
        )

        if value is not None:
            values[ATA_ATTRIBUTES[attr_id]] = value

    return values


def append_metric(lines, metric, value, labels=None):
    label_string = ""

    if labels:
        encoded = ",".join(
            f'{key}="{escape_label(val)}"'
            for key, val in sorted(labels.items())
        )

        label_string = f"{{{encoded}}}"

    lines.append(f"{metric}{label_string} {value}")


def collect_device(role, model, path, lines):
    result = run(["smartctl", "-a", "-j", path])

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        append_metric(
            lines,
            "homelab_smart_device_collection_success",
            0,
            {"device": role},
        )

        return False

    actual_model = data.get("model_name") or model

    append_metric(
        lines,
        "homelab_smart_device_info",
        1,
        {
            "device": role,
            "model": actual_model,
        },
    )

    smart_status = data.get("smart_status", {}).get("passed")

    collection_ok = smart_status is not None

    append_metric(
        lines,
        "homelab_smart_device_collection_success",
        1 if collection_ok else 0,
        {"device": role},
    )

    if smart_status is not None:
        append_metric(
            lines,
            "homelab_smart_device_health",
            1 if smart_status else 0,
            {"device": role},
        )

    temperature = numeric(
        data.get("temperature", {}).get("current")
    )

    if temperature is not None:
        append_metric(
            lines,
            "homelab_smart_temperature_celsius",
            temperature,
            {"device": role},
        )

    power_on_hours = numeric(
        data.get("power_on_time", {}).get("hours")
    )

    if power_on_hours is not None:
        append_metric(
            lines,
            "homelab_smart_power_on_hours",
            power_on_hours,
            {"device": role},
        )

    for name, value in ata_attributes(data).items():
        append_metric(
            lines,
            f"homelab_smart_{name}",
            value,
            {"device": role},
        )

    return collection_ok


def main():
    TEXTFILE_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    lines = [
        "# HELP homelab_smart_device_info SMART device information.",
        "# TYPE homelab_smart_device_info gauge",

        "# HELP homelab_smart_device_collection_success Whether SMART information was collected successfully.",
        "# TYPE homelab_smart_device_collection_success gauge",

        "# HELP homelab_smart_device_health Overall SMART device health.",
        "# TYPE homelab_smart_device_health gauge",

        "# HELP homelab_smart_temperature_celsius Device temperature in Celsius.",
        "# TYPE homelab_smart_temperature_celsius gauge",

        "# HELP homelab_smart_power_on_hours Device power-on hours.",
        "# TYPE homelab_smart_power_on_hours gauge",

        "# HELP homelab_smart_reallocated_sectors Reallocated sector count.",
        "# TYPE homelab_smart_reallocated_sectors gauge",

        "# HELP homelab_smart_reported_uncorrectable Reported uncorrectable errors.",
        "# TYPE homelab_smart_reported_uncorrectable gauge",

        "# HELP homelab_smart_pending_sectors Current pending sector count.",
        "# TYPE homelab_smart_pending_sectors gauge",

        "# HELP homelab_smart_offline_uncorrectable Offline uncorrectable sector count.",
        "# TYPE homelab_smart_offline_uncorrectable gauge",

        "# HELP homelab_smart_crc_errors Interface CRC error count.",
        "# TYPE homelab_smart_crc_errors gauge",

        "# HELP homelab_smart_collector_success Whether all configured SMART devices were collected successfully.",
        "# TYPE homelab_smart_collector_success gauge",

        "# HELP homelab_smart_collector_last_run_unixtime Unix time of the latest collector run.",
        "# TYPE homelab_smart_collector_last_run_unixtime gauge",
    ]

    try:
        discovered = discover_devices()
    except Exception:
        discovered = {}

    all_ok = True

    for role, expected_model in DEVICES.items():
        path = discovered.get(expected_model)

        if path is None:
            append_metric(
                lines,
                "homelab_smart_device_collection_success",
                0,
                {"device": role},
            )

            all_ok = False
            continue

        if not collect_device(
            role,
            expected_model,
            path,
            lines,
        ):
            all_ok = False

    append_metric(
        lines,
        "homelab_smart_collector_success",
        1 if all_ok else 0,
    )

    append_metric(
        lines,
        "homelab_smart_collector_last_run_unixtime",
        int(time.time()),
    )

    fd, temporary = tempfile.mkstemp(
        prefix=".homelab_smart.",
        suffix=".prom",
        dir=TEXTFILE_DIR,
        text=True,
    )

    try:
        with os.fdopen(fd, "w") as file:
            file.write("\n".join(lines))
            file.write("\n")

        os.chmod(temporary, 0o644)
        os.replace(temporary, OUTPUT)

    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
