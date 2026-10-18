#!/usr/bin/env python3
"""Read-only OPNsense NAT drift plan for HA01/Voice PE.

Never sends write requests. Never prints API credentials or full configuration dumps.
"""
from __future__ import annotations

import argparse
import importlib.util
import ipaddress
import json
from pathlib import Path
import stat
import subprocess
import sys
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "network" / "voice-pe.yml"
DEFAULT_CERT = Path.home() / ".config/homelab/opnsense/opnsense.crt"
DEFAULT_NETRC = Path.home() / ".config/homelab/opnsense/api.netrc"


class PlanError(Exception):
    """Non-sensitive error in plan-only workflow."""


def cidr(value: Any) -> str:
    """Normalize an address or subnet (e.g. 192.168.10.50 -> /32)."""
    return str(ipaddress.ip_network(str(value), strict=False))


def normalized(value: Any, key: str) -> str:
    """Normalize representation differences, not policy differences."""
    if value is None:
        return ""
    if key in {"source.network", "source_net", "destination_net"}:
        return cidr(value) if value != "" else ""
    if key in {"protocol", "ipprotocol", "interface"}:
        return str(value).lower()
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise PlanError("Manifest must be a YAML mapping")
        validator_path = ROOT / "scripts" / "verify-voice-pe.py"
        if not validator_path.is_file():
            raise PlanError(f"Missing validator: {validator_path}")
        spec = importlib.util.spec_from_file_location("verify_voice_pe", validator_path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.validate(data)
        return data
    except (OSError, ValueError, KeyError, yaml.YAMLError) as exc:
        raise PlanError(f"Invalid manifest: {exc}") from exc


def expected_rules(data: dict[str, Any]) -> dict[str, list[tuple[str, dict[str, str]]]]:
    """Build comparisons from intent; UUIDs are discovered at runtime."""
    op = data["opnsense"]
    expected: dict[str, list[tuple[str, dict[str, str]]]] = {"DNAT": [], "SNAT": []}
    for rule in data["nat"]["destination"]:
        expected["DNAT"].append((rule["id"], {
            "descr": rule["description"],
            "disabled": "0",
            "nordr": "0",
            "interface": rule["interface"],
            "ipprotocol": "inet",
            "protocol": "tcp",
            "source.network": cidr(rule["source"]),
            "source.not": "0",
            "destination.network": "wanip" if rule["destination"] == op["wan_ipv4"] else rule["destination"],
            "destination.port": str(rule["destination_port"]),
            "destination.not": "0",
            "target": rule["target"],
            "local-port": str(rule["target_port"]),
            "pass": "rule",
        }))
    for rule in data["nat"]["source"]:
        expected["SNAT"].append((rule["id"], {
            "description": rule["description"],
            "enabled": "1",  # SNAT uses enabled=1; DNAT uses disabled=0
            "nonat": "0",
            "interface": rule["interface"],
            "ipprotocol": "inet",
            "protocol": "tcp",
            "source_net": cidr(rule["source"]),
            "source_not": "0",
            "destination_net": cidr(rule["destination"]),
            "destination_not": "0",
            "destination_port": str(rule["destination_port"]),
            "target": "lanip" if rule["translation"] == op["lan_ipv4"] else rule["translation"],
        }))
    return expected


def assess(data: dict[str, Any], responses: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    """Compare only the four owned rules; refuse ambiguous matching."""
    assessment: list[dict[str, Any]] = []
    for kind, rules in expected_rules(data).items():
        payload = responses.get(kind)
        if not isinstance(payload, dict) or not isinstance(payload.get("rows"), list):
            raise PlanError(f"Unexpected {kind} API response (missing rows)")
        rows = payload["rows"]
        for item in rows:
            if not isinstance(item, dict):
                raise PlanError(f"Unexpected {kind} API row")
        desc_key = "descr" if kind == "DNAT" else "description"
        for rule_id, desired in rules:
            matches = [r for r in rows if r.get(desc_key) == desired[desc_key]]
            result: dict[str, Any] = {"kind": kind, "id": rule_id, "matches": len(matches)}
            if not matches:
                result.update(status="MISSING", uuid="", changes={})
            elif len(matches) != 1:
                result.update(status="AMBIGUOUS", uuid="", changes={})
            else:
                row = matches[0]
                diffs = {
                    key: {"want": normalized(want, key), "actual": normalized(row.get(key), key)}
                    for key, want in desired.items()
                    if normalized(want, key) != normalized(row.get(key), key)
                }
                result.update(
                    status="DRIFT" if diffs else "NO_CHANGE",
                    uuid=str(row.get("uuid", "")),
                    changes=diffs,
                )
            assessment.append(result)
    return assessment


def api_read(kind: str, hostname: str, ip: str, cert: Path, netrc: Path) -> dict[str, Any]:
    endpoint = {
        "DNAT": "/api/firewall/d_nat/search_rule",
        "SNAT": "/api/firewall/source_nat/search_rule",
    }[kind]
    cmd = [
        "curl", "--silent", "--show-error", "--fail-with-body",
        "--connect-timeout", "5", "--max-time", "15",
        "--noproxy", "*",
        "--resolve", f"{hostname}:443:{ip}",
        "--cacert", str(cert), "--netrc-file", str(netrc),
        "--header", "Accept: application/json",
        f"https://{hostname}{endpoint}",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PlanError(f"Unable to execute curl for {kind}: {type(exc).__name__}") from exc
    if proc.returncode:
        # Intentionally omit server response/body and curl stderr: no credentials or
        # potentially sensitive appliance payload should appear in CI logs.
        raise PlanError(f"{kind} API failed (curl exit {proc.returncode}); check TLS, credentials, role or reachability")
    try:
        parsed = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise PlanError(f"{kind} API returned invalid JSON") from exc
    if not isinstance(parsed, dict):
        raise PlanError(f"{kind} API returned unexpected JSON type")
    return parsed


def _check_credentials(cert: Path, netrc: Path) -> None:
    if not cert.is_file() or not netrc.is_file():
        raise PlanError("Missing certificate or netrc file under ~/.config/homelab/opnsense")
    if stat.S_IMODE(netrc.stat().st_mode) & 0o077:
        raise PlanError("api.netrc must not be accessible by group/others (chmod 600)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["plan"])
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--host", default="OPNsense.internal")
    parser.add_argument("--ip", default="192.168.10.1")
    parser.add_argument("--cert", type=Path, default=DEFAULT_CERT)
    parser.add_argument("--netrc", type=Path, default=DEFAULT_NETRC)
    args = parser.parse_args()
    try:
        # Hardening: no URL/path-injection via hostname or IP overrides.
        if args.host != "OPNsense.internal":
            raise PlanError("Only OPNsense.internal (current trusted SAN) is supported")
        if str(ipaddress.ip_address(args.ip)) != "192.168.10.1":
            raise PlanError("Unexpected firewall IP; verify topology before updating code")
        data = load_manifest(args.manifest)
        _check_credentials(args.cert, args.netrc)
        live = {kind: api_read(kind, args.host, args.ip, args.cert, args.netrc)
                for kind in ("DNAT", "SNAT")}
        checks = assess(data, live)
        print("OPNsense NAT plan (READ ONLY; no write requests)")
        for check in checks:
            print(f"[{check['status']}] {check['kind']} {check['id']}",
                  f"uuid={check['uuid']}" if check["uuid"] else "")
            for field, values in sorted(check["changes"].items()):
                print(f"   {field}: expected={values['want']!r} actual={values['actual']!r}")
        counts = {status: sum(x["status"] == status for x in checks)
                  for status in ("NO_CHANGE", "MISSING", "DRIFT", "AMBIGUOUS")}
        print(f"Summary: {counts}. No changes applied. Filter rules/DHCP/voice services not covered.")
        return 0 if counts["NO_CHANGE"] == 4 else 1
    except (PlanError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
