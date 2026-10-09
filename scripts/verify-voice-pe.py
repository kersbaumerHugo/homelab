#!/usr/bin/env python3
"""Validate voice-pe desired state and probe network paths. Never changes devices."""
from __future__ import annotations

import argparse
import base64
import ipaddress
import json
import os
from pathlib import Path
import socket
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import yaml

DEFAULT_FILE = Path(__file__).resolve().parents[1] / "network" / "voice-pe.yml"


def _ip(value: object) -> ipaddress.IPv4Address:
    result = ipaddress.ip_address(str(value))
    if not isinstance(result, ipaddress.IPv4Address):
        raise ValueError("Only IPv4 is supported by this transitional topology")
    return result


def _port(value: object) -> int:
    port = int(value)
    if not 1 <= port <= 65535:
        raise ValueError("TCP port must be between 1 and 65535")
    return port


def validate(data: dict) -> None:
    if data.get("schema_version") != 1 or data.get("status") != "migration-pending":
        raise ValueError("Unexpected schema version or migration status")
    op = data["opnsense"]
    ha = data["home_assistant"]
    voice = data["voice_pe"]
    phone = data["phone"]
    upstream = ipaddress.ip_network(data["upstream"]["network"], strict=True)
    lan = ipaddress.ip_network(op["lan_network"], strict=True)
    if upstream.overlaps(lan):
        raise ValueError("OPNsense WAN and LAN networks must not overlap")
    if _ip(op["wan_ipv4"]) not in upstream or _ip(voice["ipv4"]) not in upstream:
        raise ValueError("WAN or voice PE address outside Nokia subnet")
    if _ip(phone["ipv4"]) not in upstream or _ip(ha["ipv4"]) not in lan:
        raise ValueError("Phone or Home Assistant address outside its subnet")
    if _ip(op["lan_ipv4"]) not in lan:
        raise ValueError("LAN gateway outside its subnet")
    ha_port = _port(ha["http_port"])
    _port(voice["esphome_tcp_port"])
    expected_url = f"http://{op['wan_ipv4']}:18080"
    if ha["advertised_url"] != expected_url:
        raise ValueError(f"Expected advertised_url {expected_url}")
    if ha["direct_url"] != f"http://{ha['ipv4']}":
        raise ValueError("Direct URL does not match HA IPv4")
    wanted = {"phone-to-ha", "voice-to-ha", "ha-hairpin-dnat"}
    dnat = data["nat"]["destination"]
    snat = data["nat"]["source"]
    if {r["id"] for r in dnat} != wanted or len(dnat) != 3:
        raise ValueError("Exactly the 3 named destination rules are expected")
    sources = {
        "phone-to-ha": ("wan", str(_ip(phone["ipv4"])) + "/32"),
        "voice-to-ha": ("wan", str(_ip(voice["ipv4"])) + "/32"),
        "ha-hairpin-dnat": ("lan", str(_ip(ha["ipv4"])) + "/32"),
    }
    for rule in dnat:
        iface, source = sources[rule["id"]]
        if rule["interface"] != iface or rule["source"] != source:
            raise ValueError(f"Unsafe interface/source in {rule['id']}")
        if (rule["destination"] != op["wan_ipv4"]
                or _port(rule["destination_port"]) != 18080
                or rule["target"] != ha["ipv4"]
                or _port(rule["target_port"]) != ha_port):
            raise ValueError(f"Unexpected forwarding target in {rule['id']}")
        if not rule.get("description"):
            raise ValueError("All rules must have a description for adoption")
    if len(snat) != 1 or snat[0]["id"] != "ha-hairpin-snat":
        raise ValueError("Exactly one source NAT rule expected")
    rule = snat[0]
    if (rule["interface"] != "lan" or rule["source"] != f"{ha['ipv4']}/32"
            or rule["destination"] != ha["ipv4"]
            or _port(rule["destination_port"]) != ha_port
            or rule["translation"] != op["lan_ipv4"]):
        raise ValueError("Unexpected source NAT rule")


def probe(data: dict) -> bool:
    targets = [
        ("HA direct", data["home_assistant"]["ipv4"], data["home_assistant"]["http_port"]),
        ("HA via WAN redirect", data["opnsense"]["wan_ipv4"], 18080),
        ("ESPHome API", data["voice_pe"]["ipv4"], data["voice_pe"]["esphome_tcp_port"]),
    ]
    ok = True
    for name, host, port in targets:
        try:
            with socket.create_connection((host, int(port)), timeout=4):
                print(f"[OK] {name}: {host}:{port}")
        except OSError as exc:
            ok = False
            print(f"[FAIL] {name}: {host}:{port} ({exc.__class__.__name__})")
    print("NOTE: probe results apply ONLY to the host running this script.")
    print("      To validate HAOS hairpin, run the documented probe inside its Core container.")
    return ok


def inventory(data: dict) -> bool:
    """Read-only MVC API scan; GUI/legacy firewall rules may not be returned."""
    url = os.environ.get("OPNSENSE_URL", data["opnsense"]["management_url"]).rstrip("/")
    key = os.environ.get("OPNSENSE_API_KEY")
    secret = os.environ.get("OPNSENSE_API_SECRET")
    if not key or not secret:
        raise ValueError("Set OPNSENSE_API_KEY and OPNSENSE_API_SECRET in environment")
    ctx = ssl.create_default_context(cafile=os.environ.get("OPNSENSE_CA_BUNDLE") or None)
    auth = base64.b64encode(f"{key}:{secret}".encode()).decode()
    descriptions = {r["description"] for r in data["nat"]["destination"] + data["nat"]["source"]}
    endpoints = {
        "DNAT": "/api/firewall/d_nat/searchRule",
        "SNAT": "/api/firewall/source_nat/searchRule",
        "Filter": "/api/firewall/filter/searchRule",
        "Dnsmasq hosts": "/api/dnsmasq/settings/searchHost",
    }
    all_ok = True
    for kind, endpoint in endpoints.items():
        req = Request(url + endpoint, headers={"Authorization": f"Basic {auth}", "Accept": "application/json"})
        try:
            with urlopen(req, timeout=10, context=ctx) as response:
                payload = json.load(response)
            rows = payload.get("rows")
            if not isinstance(rows, list):
                print(f"[UNKNOWN] {kind}: API response missing rows; do not assume no rules")
                all_ok = False
                continue
            print(f"[{kind}] API rows={len(rows)}")
            matched = [r for r in rows if r.get("description") in descriptions]
            for r in matched:
                # Deliberately never print rule JSON, auth, or configuration exports.
                print(f"  [MATCH] {r.get('description')} uuid={r.get('uuid', 'unknown')}")
            if kind in ("DNAT", "SNAT") and not matched:
                print("  [NOTE] No matching MVC rules; legacy GUI rules may be invisible to this API.")
        except (HTTPError, URLError, TimeoutError, OSError, ValueError) as exc:
            all_ok = False
            print(f"[UNAVAILABLE] {kind}: {type(exc).__name__}; check API role, CA and OPNsense version")
    print("READ ONLY. Does not confirm PF active rules or exact field equality.")
    print("Never auto-create duplicates until legacy rules have been reconciled.")
    return all_ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "probe", "api-inventory"))
    parser.add_argument("--file", type=Path, default=DEFAULT_FILE)
    args = parser.parse_args()
    try:
        data = yaml.safe_load(args.file.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("Expected a YAML mapping")
        validate(data)
        print("[OK] Voice PE desired-state manifest validated")
        if args.command == "validate":
            return 0
        return 0 if (probe(data) if args.command == "probe" else inventory(data)) else 1
    except (KeyError, ValueError, OSError, yaml.YAMLError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
