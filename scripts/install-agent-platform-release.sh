#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"
VMID="${AGENT_CT_ID:-102}"

RELEASE="${AGENT_PLATFORM_RELEASE:-v0.1.0}"
REVISION="${AGENT_PLATFORM_REVISION:-814a157d373f749aa2fdeaafd51237a156786ec9}"

BASE_DIR="/opt/agent-platform"
RELEASE_DIR="${BASE_DIR}/releases/${RELEASE}"
ARCHIVE="/tmp/agent-platform-${REVISION}.tar.gz"
SOURCE_URL="https://github.com/kersbaumerHugo/agent-platform/archive/${REVISION}.tar.gz"

remote() {
    local cmd
    printf -v cmd '%q ' "$@"
    printf '%s\n' "$cmd" | ssh -T "$PVE_HOST" 'bash -se'
}

ct() {
    remote pct exec "$VMID" -- "$@"
}

echo "========================================"
echo " Agent Platform release installation"
echo "========================================"
echo "PVE host : $PVE_HOST"
echo "VMID     : $VMID"
echo "Release  : $RELEASE"
echo "Revision : $REVISION"
echo

echo "==> Preflight"

remote pct status "$VMID" |
    grep -q 'status: running'

echo "[OK] agent01 running"

ct getent hosts github.com >/dev/null
echo "[OK] DNS/network available"

ct python3 -c \
    'import sys; raise SystemExit(sys.version_info < (3, 12))'

echo "[OK] Python >= 3.12"

if ct test -e "$RELEASE_DIR"; then
    EXISTING_REVISION="$(
        ct cat "${RELEASE_DIR}/REVISION" 2>/dev/null || true
    )"

    if [[ "$EXISTING_REVISION" != "$REVISION" ]]; then
        echo "[ERROR] $RELEASE_DIR already exists with a different revision."
        echo "Expected: $REVISION"
        echo "Found   : ${EXISTING_REVISION:-<missing>}"
        exit 1
    fi

    ct test -x "${RELEASE_DIR}/.venv/bin/python"
    ct "${RELEASE_DIR}/.venv/bin/python" -c \
        'import agent_platform'

    echo "[OK] release already installed and verified"
    echo
    ct bash -lc \
        "printf 'REVISION='; cat '${RELEASE_DIR}/REVISION'; \
         printf 'PYTHON='; cat '${RELEASE_DIR}/PYTHON'; \
         du -sh '${RELEASE_DIR}'"
    exit 0
fi

echo
echo "==> Installing minimum prerequisites"

ct bash -lc '
    apt-get update
    DEBIAN_FRONTEND=noninteractive \
      apt-get install -y \
        ca-certificates \
        curl \
        python3-venv
'

echo "[OK] prerequisites installed"

echo
echo "==> Downloading immutable revision"

ct curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --output "$ARCHIVE" \
    "$SOURCE_URL"

SOURCE_SHA256="$(
    ct sha256sum "$ARCHIVE" |
        awk '{print $1}'
)"

echo "[OK] source archive downloaded"
echo "     sha256: $SOURCE_SHA256"

echo
echo "==> Installing release"

START_EPOCH="$(date +%s)"

ct bash -s -- \
    "$BASE_DIR" \
    "$RELEASE" \
    "$REVISION" \
    "$ARCHIVE" \
    "$SOURCE_SHA256" <<'REMOTE_SCRIPT'
set -euo pipefail

BASE_DIR="$1"
RELEASE="$2"
REVISION="$3"
ARCHIVE="$4"
SOURCE_SHA256="$5"

RELEASE_DIR="${BASE_DIR}/releases/${RELEASE}"
STAGE="${BASE_DIR}/releases/.staging-${RELEASE}-$$"

cleanup() {
    local rc=$?
    rm -rf "$STAGE"
    exit "$rc"
}
trap cleanup EXIT

install -d -m 0755 "${BASE_DIR}/releases"
install -d -m 0755 "$STAGE/app"

tar \
    -xzf "$ARCHIVE" \
    --strip-components=1 \
    -C "$STAGE/app"

python3 -m venv "$STAGE/.venv"

"$STAGE/.venv/bin/python" -m pip \
    install \
    --disable-pip-version-check \
    "$STAGE/app"

printf '%s\n' "$REVISION" > "$STAGE/REVISION"
printf '%s\n' "$SOURCE_SHA256" > "$STAGE/SOURCE_SHA256"
python3 --version > "$STAGE/PYTHON"

"$STAGE/.venv/bin/python" -m pip \
    freeze --all \
    > "$STAGE/DEPENDENCIES.txt"

"$STAGE/.venv/bin/python" -c \
    'import agent_platform'

mv "$STAGE" "$RELEASE_DIR"

trap - EXIT
REMOTE_SCRIPT

END_EPOCH="$(date +%s)"
INSTALL_SECONDS="$((END_EPOCH - START_EPOCH))"

ct rm -f "$ARCHIVE"

echo "[OK] release installed"

echo
echo "==> Verifying release identity"

INSTALLED_REVISION="$(
    ct cat "${RELEASE_DIR}/REVISION"
)"

[[ "$INSTALLED_REVISION" == "$REVISION" ]]

ct test -s "${RELEASE_DIR}/DEPENDENCIES.txt"
ct test -s "${RELEASE_DIR}/SOURCE_SHA256"
ct test -x "${RELEASE_DIR}/.venv/bin/python"

echo "[OK] exact revision recorded"
echo "[OK] dependency snapshot recorded"

echo
echo "==> Evidence"

ct bash -lc "
    printf 'Release: '; printf '%s\n' '$RELEASE'
    printf 'Revision: '; cat '${RELEASE_DIR}/REVISION'
    printf 'Source SHA256: '; cat '${RELEASE_DIR}/SOURCE_SHA256'
    printf 'Python: '; cat '${RELEASE_DIR}/PYTHON'
    printf 'Disk usage: '; du -sh '${RELEASE_DIR}' | awk '{print \$1}'
    printf 'Dependencies: '; wc -l < '${RELEASE_DIR}/DEPENDENCIES.txt'
"

echo "Install duration: ${INSTALL_SECONDS}s"

echo
echo "========================================"
echo " Phase 2 release installation successful ✅"
echo " Gate P2 release identity proven ✅"
echo "========================================"
