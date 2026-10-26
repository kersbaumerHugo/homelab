#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"

usage() {
  echo "Usage: $0 status | plan {ai|gtnh}" >&2
  exit 2
}

case "${1:-}" in
  status)
    [[ $# -eq 1 ]] || usage
    action=status
    mode=none
    ;;
  plan)
    [[ $# -eq 2 ]] || usage
    action=plan
    mode="$2"
    [[ "$mode" == ai || "$mode" == gtnh ]] || usage
    ;;
  *)
    usage
    ;;
esac

ssh -o BatchMode=yes -T "$PVE_HOST" \
  bash -s -- "$action" "$mode" <<'REMOTE'
set -euo pipefail

action="$1"
mode="$2"
THERMAL_LIMIT_C=70  # Conservative planning gate, not a safe operating limit.

state() {
  local result
  if ! result="$(qm status "$1" 2>&1)"; then
    case "$result" in
      *"does not exist"*)
        echo absent
        return 0
        ;;
      *)
        echo "BLOCKED: cannot read VM $1 state: $result" >&2
        return 1
        ;;
    esac
  fi

  case "$result" in
    "status: running"|"status: stopped")
      echo "${result#status: }"
      ;;
    *)
      echo "BLOCKED: unexpected VM $1 state: $result" >&2
      return 1
      ;;
  esac
}

ai="$(state 103)"
gtnh="$(state 105)"
restore="$(state 905)"

echo "===== PVE01 ====="
hostname

echo "===== WORKLOADS ====="
printf '103 inference01: %s\n' "$ai"
printf '105 gtnh01:     %s\n' "$gtnh"
printf '905 restore:    %s\n' "$restore"

echo "===== TEMPERATURA ====="
temperature_line="$(sensors 2>/dev/null | grep -m1 'Package id 0:' || true)"
printf '%s\n' "${temperature_line:-unavailable}"

[[ "$action" == status ]] && exit 0

echo
echo "===== DRY RUN: $mode ====="

if [[ "$ai" == absent || "$gtnh" == absent ]]; then
  echo "BLOCKED: main VM missing."
  exit 1
fi

if [[ "$restore" == running ]]; then
  echo "BLOCKED: restore VM 905 is running."
  exit 1
fi

if [[ "$ai" == running && "$gtnh" == running ]]; then
  echo "BLOCKED: AI and GTNH are running simultaneously."
  exit 1
fi

# Fail closed: no sensor data or unsupported output must block planning.
if [[ ! "$temperature_line" =~ \+([0-9]+)(\.[0-9]+)?°C ]]; then
  echo "BLOCKED: CPU temperature unavailable or invalid."
  exit 1
fi

temperature_c="${BASH_REMATCH[1]}"
if (( temperature_c >= THERMAL_LIMIT_C )); then
  echo "BLOCKED: CPU at ${temperature_c} C (gate: < ${THERMAL_LIMIT_C} C)."
  exit 1
fi

if [[ "$mode" == gtnh ]]; then
  source_id=103
  source_state="$ai"
  target_id=105
  target_state="$gtnh"
else
  source_id=105
  source_state="$gtnh"
  target_id=103
  target_state="$ai"
fi

if [[ "$source_state" == running ]]; then
  if [[ "$source_id" == 105 ]]; then
    echo "1. Stop Minecraft gracefully and save the world."
  fi
  echo "2. Request graceful shutdown of VM $source_id."
  echo "3. Confirm that VM $source_id is stopped."
else
  echo "Source VM $source_id is already stopped."
fi

if [[ "$target_state" == stopped ]]; then
  echo "4. Re-check thermal and resource preconditions before any start."
  echo "5. Start VM $target_id."
  echo "6. Verify VM and workload health."
else
  echo "Target VM $target_id is already running."
fi

echo
echo "DRY RUN: no changes made."
REMOTE
