#!/usr/bin/env python3
"""Check and save a validated OPNsense config backup through HTTPS API.

No plaintext configuration is saved to disk. Never commit encrypted backups
without a deliberate policy: the configuration still contains sensitive data.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from xml.etree import ElementTree as ET

HOST = "OPNsense.internal"
IP = "192.168.10.1"
ENDPOINT = f"https://{HOST}/api/core/backup/download/this"
DEFAULT_CERT = Path.home() / ".config/homelab/opnsense/opnsense.crt"
DEFAULT_NETRC = Path.home() / ".config/homelab/opnsense/api.netrc"
DEFAULT_OUTDIR = Path.home() / ".local/state/homelab/opnsense"
MAX_BYTES = 32 * 1024 * 1024


class BackupError(Exception):
    """Safe-to-print error without private configuration content."""


def credentials_ok(cert: Path, netrc: Path) -> None:
    if not cert.is_file() or not netrc.is_file():
        raise BackupError("Certificate or API netrc is missing")
    if stat.S_IMODE(netrc.stat().st_mode) & 0o077:
        raise BackupError("api.netrc permissions are too broad; use chmod 600")


def download(cert: Path, netrc: Path) -> bytes:
    cmd = [
        "curl", "--silent", "--show-error", "--fail-with-body",
        "--connect-timeout", "5", "--max-time", "30",
        "--noproxy", "*", "--resolve", f"{HOST}:443:{IP}",
        "--cacert", str(cert), "--netrc-file", str(netrc),
        "--header", "Accept: application/xml",
        ENDPOINT,
    ]
    try:
        process = subprocess.run(cmd, capture_output=True, check=False, timeout=35)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise BackupError(f"API request could not run ({type(exc).__name__})") from exc
    if process.returncode != 0:
        # No server body/stderr: config/history endpoints may include secrets.
        raise BackupError(f"Backup API request failed (curl exit {process.returncode}); check API permissions, TLS and endpoint")
    return process.stdout


def validate_xml(payload: bytes) -> None:
    if not payload or len(payload) > MAX_BYTES:
        raise BackupError("Backup response is empty or larger than allowed maximum")
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as exc:
        # OPNsense versions have previously shipped malformed XML backups.
        raise BackupError("Backup response is not well-formed XML; refusing to save") from exc
    if root.tag.lower() != "opnsense":
        raise BackupError("Backup response root is not <opnsense>; refusing to save")
    if len(root) == 0:
        raise BackupError("Backup response has no configuration sections")


def encrypted_save(payload: bytes, outdir: Path, recipient: str) -> Path:
    if not re.fullmatch(r"age1[a-z0-9]{20,}", recipient):
        raise BackupError("AGE_RECIPIENT is missing or does not look like an age public recipient")
    if shutil.which("age") is None:
        raise BackupError("age executable was not found; install age first")
    old_umask = os.umask(0o077)
    try:
        outdir.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Shared/user-specified output directory is rejected if writable by others.
        if stat.S_IMODE(outdir.stat().st_mode) & 0o022:
            raise BackupError("Output directory must not be group/world writable")
        with tempfile.NamedTemporaryFile(prefix=".opnsense-", suffix=".tmp", dir=outdir, delete=False) as stream:
            temp_path = Path(stream.name)
            try:
                try:
                    proc = subprocess.run(
                        ["age", "-r", recipient], input=payload, stdout=stream,
                        stderr=subprocess.PIPE, check=False, timeout=45,
                    )
                except (OSError, subprocess.TimeoutExpired) as exc:
                    raise BackupError(f"age encryption failed ({type(exc).__name__})") from exc
                if proc.returncode != 0:
                    raise BackupError("age encryption failed; encrypted output discarded")
                stream.flush()
                os.fsync(stream.fileno())
                if temp_path.stat().st_size < 100:
                    raise BackupError("Encrypted output unexpectedly small")
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                final_path = outdir / f"opnsense-config-{stamp}-{secrets.token_hex(4)}.xml.age"
                os.replace(temp_path, final_path)
                return final_path
            finally:
                temp_path.unlink(missing_ok=True)
    finally:
        os.umask(old_umask)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "save"))
    parser.add_argument("--cert", type=Path, default=DEFAULT_CERT)
    parser.add_argument("--netrc", type=Path, default=DEFAULT_NETRC)
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    args = parser.parse_args()
    try:
        credentials_ok(args.cert, args.netrc)
        if args.command == "save":
            # Check preconditions before downloading configuration with secrets.
            recipient = os.getenv("AGE_RECIPIENT", "")
            if not re.fullmatch(r"age1[a-z0-9]{20,}", recipient):
                raise BackupError("Set AGE_RECIPIENT to your age public recipient")
            if shutil.which("age") is None:
                raise BackupError("Install the age CLI before attempting save")
        xml = download(args.cert, args.netrc)
        validate_xml(xml)
        if args.command == "check":
            print("[OK] OPNsense backup endpoint accessible; XML well formed (not saved)")
        else:
            dest = encrypted_save(xml, args.outdir, recipient)
            print(f"[OK] Encrypted backup written to: {dest}")
            print("[NEXT] Verify decryptability using a separately secured age identity, and keep an off-host copy")
        return 0
    except BackupError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
