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

log_action() {
  if [[ -n "${MOCK_ACTION_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "$MOCK_ACTION_LOG"
  fi
}

get_state() {
  local id="$1" statefile="${MOCK_STATE_DIR:-}/$1"
  if [[ -n "${MOCK_STATE_DIR:-}" && -f "$statefile" ]]; then
    cat "$statefile"
  else
    case "$id" in
      103) echo "${MOCK_AI_STATE:-stopped}" ;;
      105) echo "${MOCK_GT_STATE:-stopped}" ;;
      905) echo "${MOCK_RESTORE_STATE:-stopped}" ;;
      *) exit 99 ;;
    esac
  fi
}

case "${1:-}" in
  status)
    [[ $# -eq 2 ]] || exit 99
    result="$(get_state "$2")"
    case "$result" in
      absent) echo "Configuration file for VM $2 does not exist" >&2; exit 2 ;;
      error) echo 'Proxmox API unavailable' >&2; exit 5 ;;
      *) echo "status: $result" ;;
    esac
    ;;
  config)
    [[ "$2" == 103 || "$2" == 105 ]] || exit 99
    printf 'memory: %s\n' "${MOCK_VM_RAM_MIB:-8192}"
    ;;
  shutdown)
    [[ "$2" == 103 || "$2" == 105 ]] || exit 99
    log_action "shutdown $2"
    [[ "${MOCK_FAIL_SHUTDOWN:-0}" != 1 ]] || exit 8
    [[ -n "${MOCK_STATE_DIR:-}" ]] || exit 99
    echo stopped > "$MOCK_STATE_DIR/$2"
    ;;
  start)
    [[ "$2" == 103 || "$2" == 105 ]] || exit 99
    log_action "start $2"
    [[ "${MOCK_FAIL_START:-0}" != 1 ]] || exit 8
    [[ -n "${MOCK_STATE_DIR:-}" ]] || exit 99
    echo running > "$MOCK_STATE_DIR/$2"
    ;;
  agent)
    [[ "$3" == ping ]] || exit 99
    [[ "${MOCK_FAIL_AGENT:-0}" != 1 ]] || exit 9
    ;;
  guest)
    [[ "$2" == exec ]] || exit 99
    if [[ "$*" == *'docker compose stop'* ]]; then
      log_action "docker stop $3"
      if [[ "${MOCK_FAIL_DOCKER_STOP:-0}" == 1 ]]; then
        printf '{"exited":1,"exitcode":1,"err-data":"simulated failure"}\n'
      else
        printf '{"exited":1,"exitcode":0}\n'
      fi
    elif [[ "$*" == *'docker compose up -d'* ]]; then
      log_action "docker up $3"
      printf '{"exited":1,"exitcode":0}\n'
    elif [[ "$*" == *'docker inspect'* ]]; then
      log_action "docker health $3"
      printf '{"exited":1,"exitcode":0,"out-data":"%s\\n"}\n' "${MOCK_DOCKER_HEALTH:-healthy}"
    else
      exit 99
    fi
    ;;
  *) echo "Unexpected VM-changing command: $*" >&2; exit 99 ;;
esac
FAKE_QM

cat > "$TMP/bin/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
exit 0
FAKE_SLEEP
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


# Real switch tests are run with isolated in-memory/proxy VM states.
mkdir -p "$TMP/states"
export MOCK_STATE_DIR="$TMP/states"
export MOCK_ACTION_LOG="$TMP/actions.log"
export HOMELAB_LOCK_FILE="$TMP/switch.lock"
export HOMELAB_MEMINFO_FILE="$TMP/meminfo"
cat > "$HOMELAB_MEMINFO_FILE" <<'MEMINFO'
MemAvailable: 30000000 kB
MEMINFO
reset_states() {
  printf 'stopped\n' > "$MOCK_STATE_DIR/103"
  printf 'stopped\n' > "$MOCK_STATE_DIR/105"
  printf 'stopped\n' > "$MOCK_STATE_DIR/905"
  : > "$MOCK_ACTION_LOG"
}

reset_states
expect_block 'switch disabled by default' 'switching is disabled' \
  "$script" switch gtnh --execute
[[ ! -s "$MOCK_ACTION_LOG" ]] || fail 'disabled did not mutate' "$(cat "$MOCK_ACTION_LOG")"

reset_states
expect_ok 'switch to GTNH (explicit opt-in)' 'SUCCESS: switched to gtnh' \
  env HOMELAB_SWITCH_ENABLED=1 "$script" switch gtnh --execute
[[ "$(cat "$MOCK_STATE_DIR/105")" == running ]] || fail 'gtnh not running' ''
grep -q '^docker up 105$' "$MOCK_ACTION_LOG" || fail 'Docker not started' ''

reset_states
printf 'running\n' > "$MOCK_STATE_DIR/105"
expect_ok 'switch GTNH to AI' 'SUCCESS: switched to ai' \
  env HOMELAB_SWITCH_ENABLED=1 "$script" switch ai --execute
[[ "$(cat "$MOCK_STATE_DIR/105")" == stopped ]] || fail 'GTNH not stopped' ''
[[ "$(cat "$MOCK_STATE_DIR/103")" == running ]] || fail 'inference not started' ''
order="$(cat "$MOCK_ACTION_LOG")"
[[ "$order" == $'docker stop 105\nshutdown 105\nstart 103' ]] || fail 'wrong shutdown order' "$order"

reset_states
printf 'running\n' > "$MOCK_STATE_DIR/105"
expect_block 'guest Docker stop failure blocks switch' \
  'did not shut down safely' \
  env HOMELAB_SWITCH_ENABLED=1 MOCK_FAIL_DOCKER_STOP=1 \
  "$script" switch ai --execute
! grep -q '^start 103$' "$MOCK_ACTION_LOG" || fail 'unsafe start after failed stop' ''

reset_states
printf 'running\n' > "$MOCK_STATE_DIR/105"
expect_block 'shutdown failure blocks switch' 'did not shut down safely' \
  env HOMELAB_SWITCH_ENABLED=1 MOCK_FAIL_SHUTDOWN=1 \
  "$script" switch ai --execute
! grep -q '^start 103$' "$MOCK_ACTION_LOG" || fail 'unsafe start after shutdown error' ''

reset_states
expect_block 'thermal gate blocks execution' 'BLOCKED: CPU at 76 C' \
  env HOMELAB_SWITCH_ENABLED=1 MOCK_TEMP=76 "$script" switch gtnh --execute
[[ ! -s "$MOCK_ACTION_LOG" ]] || fail 'thermal gate mutated VMs' ''

reset_states
printf 'running\n' > "$MOCK_STATE_DIR/905"
expect_block 'restore VM blocks execution' 'restore VM 905 is running' \
  env HOMELAB_SWITCH_ENABLED=1 "$script" switch gtnh --execute
[[ ! -s "$MOCK_ACTION_LOG" ]] || fail 'restore guard mutated VMs' ''

reset_states
cat > "$HOMELAB_MEMINFO_FILE" <<'MEMINFO'
MemAvailable: 2000000 kB
MEMINFO
expect_block 'insufficient host RAM blocks start' 'insufficient host memory' \
  env HOMELAB_SWITCH_ENABLED=1 "$script" switch gtnh --execute
[[ ! -s "$MOCK_ACTION_LOG" ]] || fail 'RAM gate mutated VMs' ''
cat > "$HOMELAB_MEMINFO_FILE" <<'MEMINFO'
MemAvailable: 30000000 kB
MEMINFO

reset_states
expect_block 'start failure propagated' 'failed to switch to gtnh' \
  env HOMELAB_SWITCH_ENABLED=1 MOCK_FAIL_START=1 \
  "$script" switch gtnh --execute
[[ "$(cat "$MOCK_STATE_DIR/105")" == stopped ]] || fail 'failed target running' ''

reset_states
expect_block 'unhealthy Docker triggers graceful shutdown' 'failed to switch to gtnh' \
  env HOMELAB_SWITCH_ENABLED=1 MOCK_DOCKER_HEALTH=unhealthy \
  "$script" switch gtnh --execute
[[ "$(cat "$MOCK_STATE_DIR/105")" == stopped ]] || fail 'unhealthy target left running' ''

echo 'All mocked workload mode tests passed.'
