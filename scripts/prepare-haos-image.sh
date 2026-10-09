#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="18.3"
ASSET="haos_ova-${VERSION}.qcow2.xz"
DEST="$ROOT/.cache/haos"

URL="https://github.com/home-assistant/operating-system/releases/download/${VERSION}/${ASSET}"
API="https://api.github.com/repos/home-assistant/operating-system/releases/tags/${VERSION}"

for cmd in curl jq sha256sum xz; do
    command -v "$cmd" >/dev/null || {
        echo "Missing dependency: $cmd" >&2
        exit 1
    }
done

mkdir -p "$DEST"

echo "==> Fetching official release metadata"

DIGEST="$(
    curl -fsSL "$API" |
        jq -r --arg asset "$ASSET" \
        '.assets[] | select(.name == $asset) | .digest // empty'
)"

[[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "Missing valid SHA-256 in release metadata" >&2
    exit 1
}

EXPECTED="${DIGEST#sha256:}"

echo "==> Downloading HAOS $VERSION"

curl -fL \
    --retry 3 \
    -o "$DEST/$ASSET" \
    "$URL"

echo "==> Verifying SHA-256"

echo "$EXPECTED  $DEST/$ASSET" |
    sha256sum -c -

echo "==> Extracting QCOW2"

xz -dkf "$DEST/$ASSET"

echo "==> Image ready"
echo "$DEST/${ASSET%.xz}"
