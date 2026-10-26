#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
# The remote here-doc is evaluated locally with mocked commands.
while [[ $# -gt 0 && "$1" != bash ]]; do shift; done
[[ $# -gt 0 ]] || exit 99
exec "$@"
FAKE_SSH

cat > "$TMP/bin/qm" <<'FAKE_QM'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == status && $# -eq 2 ]] || {
  echo 'Unexpected VM-changing command' >&2
  exit 99
}

case "$2" in
  103) result="${MOCK_AI_STATE:-stopped}" ;;
  105) result="${MOCK_GT_STATE:-stopped}" ;;
  905) result="${MOCK_RESTORE_STATE:-stopped}" ;;
  *) exit 99 ;;
esac

case "$result" in
  absent)
    echo "Configuration file for VM $2 does not exist" >&2
    exit 2
    ;;
  error)
    echo 'Proxmox API unavailable' >&2
    exit 5
    ;;
  *) echo "status: $result" ;;
esac
FAKE_QM

cat > "$TMP/bin/sensors" <<'FAKE_SENSORS'
#!/usr/bin/env bash
set -euo pipefail
[[ "${MOCK_TEMP:-41}" == missing ]] && exit 1
printf 'Package id 0:  +%s°C  (high = +86.0°C, crit = +100.0°C)\n' "${MOCK_TEMP:-41}"
FAKE_SENSORS
chmod +x "$TMP/bin/"*

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n%s\n' "$1" "$2" >&2; exit 1; }

expect_ok() {
  local name="$1" match="$2" output
  shift 2
  if ! output="$(env PATH="$TMP/bin:$PATH" "$@" 2>&1)"; then
    fail "$name" "$output"
  fi
  [[ "$output" == *"$match"* ]] || fail "$name" "$output"
  pass "$name"
}

expect_block() {
  local name="$1" match="$2" output
  shift 2
  if output="$(env PATH="$TMP/bin:$PATH" "$@" 2>&1)"; then
    fail "$name (unexpected success)" "$output"
  fi
  [[ "$output" == *"$match"* ]] || fail "$name" "$output"
  pass "$name"
}

script="$ROOT/scripts/workload-mode.sh"
expect_ok 'status read-only with sensor' 'Package id 0:' "$script" status
expect_ok 'plan GTNH' 'Start VM 105' "$script" plan gtnh
expect_ok 'plan AI' 'Start VM 103' "$script" plan ai
expect_ok 'stop world before AI' 'save the world' \
  env MOCK_GT_STATE=running "$script" plan ai
expect_ok 'restore VM absent' 'DRY RUN' \
  env MOCK_RESTORE_STATE=absent "$script" plan gtnh
expect_block 'high temperature' 'BLOCKED: CPU at 76 C' \
  env MOCK_TEMP=76 "$script" plan gtnh
expect_block 'temperature threshold' 'BLOCKED: CPU at 70 C' \
  env MOCK_TEMP=70 "$script" plan ai
expect_block 'temperature missing' 'temperature unavailable' \
  env MOCK_TEMP=missing "$script" plan gtnh
expect_block 'restore VM running' 'restore VM 905' \
  env MOCK_RESTORE_STATE=running "$script" plan gtnh
expect_block 'both VMs running' 'running simultaneously' \
  env MOCK_AI_STATE=running MOCK_GT_STATE=running "$script" plan ai
expect_block 'main VM missing' 'main VM missing' \
  env MOCK_GT_STATE=absent "$script" plan gtnh
expect_block 'status API failure' 'cannot read VM 905' \
  env MOCK_RESTORE_STATE=error "$script" plan gtnh
expect_block 'unknown VM state' 'unexpected VM 103 state' \
  env MOCK_AI_STATE=paused "$script" plan ai
expect_block 'invalid input' 'Usage:' "$script" switch ai

echo 'All mocked workload mode tests passed.'
