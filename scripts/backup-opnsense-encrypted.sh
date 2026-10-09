#!/usr/bin/env bash
# Encrypted, streaming OPNsense configuration snapshot. Requires SSH read access.
set -euo pipefail

: "${AGE_RECIPIENT:?Set AGE_RECIPIENT to your age public recipient (not a secret)}"
: "${OPNSENSE_SSH_HOST:?Set OPNSENSE_SSH_HOST (e.g. root@192.168.10.1)}"

command -v age >/dev/null || { echo "[ERROR] age is required" >&2; exit 1; }
command -v ssh >/dev/null || { echo "[ERROR] ssh is required" >&2; exit 1; }

OUTDIR="${OPNSENSE_BACKUP_DIR:-$HOME/.local/state/homelab/opnsense}"
umask 077
mkdir -p "$OUTDIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FINAL="$OUTDIR/opnsense-config-$STAMP.xml.age"
TMP="$(mktemp "$OUTDIR/.config.XXXXXXXX")"
trap 'rm -f "$TMP"' EXIT

# This script does NOT enable SSH or escalate privileges automatically.
# The file is encrypted as bytes stream in; never store plaintext config.xml.
ssh -o BatchMode=yes "$OPNSENSE_SSH_HOST" 'cat /conf/config.xml' \
  | age -r "$AGE_RECIPIENT" -o "$TMP"
test -s "$TMP"
mv "$TMP" "$FINAL"
printf '[OK] Encrypted OPNsense backup: %s\n' "$FINAL"
printf 'Store the age identity/restore key separately and test recovery.\n'
