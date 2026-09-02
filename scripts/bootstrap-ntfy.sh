#!/usr/bin/env bash
# Remote commands intentionally expand PVE_HOST/CT_ID on the SSH client.
# shellcheck disable=SC2029
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
CT_ID="${CT_ID:-100}"

remote() {
    ssh "$PVE_HOST" \
        "pct exec $CT_ID -- bash -lc $(printf '%q' "$1")"
}

echo "==> Installing ntfy repository"

# $ARCH is intentionally expanded inside mon01.
# shellcheck disable=SC2016
remote '
mkdir -p /etc/apt/keyrings

curl -L \
  -o /etc/apt/keyrings/ntfy.gpg \
  https://archive.ntfy.sh/apt/keyring.gpg

apt-get install -y apt-transport-https

ARCH="$(dpkg --print-architecture)"

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/ntfy.gpg] https://archive.ntfy.sh/apt stable main" \
  > /etc/apt/sources.list.d/ntfy.list

apt-get update
apt-get install -y ntfy
'

echo "==> ntfy installed successfully"
