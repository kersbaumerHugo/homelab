#!/usr/bin/env bash
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve01}"

usage() {
  echo 'Usage: workload-mode.sh status | plan {ai|gtnh} | switch {ai|gtnh} --execute' >&2
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
    ;;
  switch)
    [[ $# -eq 3 && "$3" == --execute ]] || usage
    action=switch
    mode="$2"
    if [[ "${HOMELAB_SWITCH_ENABLED:-0}" != 1 ]]; then
      echo 'BLOCKED: switching is disabled (HOMELAB_SWITCH_ENABLED != 1).' >&2
      exit 1
    fi
    ;;
  *) usage ;;
esac

if [[ "$action" != status && "$mode" != ai && "$mode" != gtnh ]]; then
  usage
fi

ssh -o BatchMode=yes -T "$PVE_HOST" \
  bash -s -- "$action" "$mode" <<'REMOTE'
set -euo pipefail

action="$1"
mode="$2"
THERMAL_LIMIT_C=70  # Conservative operational gate, NOT a safe temperature guarantee.

state() {
  local result
  if ! result="$(qm status "$1" 2>&1)"; then
    case "$result" in
      *"does not exist"*) echo absent; return 0 ;;
      *) echo "BLOCKED: cannot read VM $1 state: $result" >&2; return 1 ;;
    esac
  fi
  case "$result" in
    'status: running'|'status: stopped') echo "${result#status: }" ;;
    *) echo "BLOCKED: unexpected VM $1 state: $result" >&2; return 1 ;;
  esac
}

# Failure is closed: unavailable sensor data, invalid output or >= 70 C all block.
thermal_gate() {
  local line temp
  line="$(sensors 2>/dev/null | grep -m1 'Package id 0:' || true)"
  if [[ ! "$line" =~ \+([0-9]+)(\.[0-9]+)?°C ]]; then
    echo 'BLOCKED: CPU temperature unavailable or invalid.' >&2
    return 1
  fi
  temp="${BASH_REMATCH[1]}"
  if (( temp >= THERMAL_LIMIT_C )); then
    echo "BLOCKED: CPU at ${temp} C (gate: < ${THERMAL_LIMIT_C} C)." >&2
    return 1
  fi
  printf 'CPU gate: %s C (< %s C)\n' "$temp" "$THERMAL_LIMIT_C"
}

# This runs AFTER the source VM stopped. We leave 2 GiB spare for pve01
# and other guests; do not assume ballooning is enabled on VM 105.
memory_gate() {
  local id="$1" cfg requested_mib available_kib
  if ! cfg="$(qm config "$id" 2>/dev/null)"; then
    echo "BLOCKED: unable to read VM $id memory configuration." >&2
    return 1
  fi
  requested_mib="$(awk '$1 == "memory:" { print $2; exit }' <<< "$cfg")"
  available_kib="$(awk '$1 == "MemAvailable:" { print $2; exit }' \
    "${HOMELAB_MEMINFO_FILE:-/proc/meminfo}")"
  if [[ ! "$requested_mib" =~ ^[0-9]+$ || ! "$available_kib" =~ ^[0-9]+$ ]]; then
    echo 'BLOCKED: memory resource data missing or invalid.' >&2
    return 1
  fi
  if (( available_kib < (requested_mib + 2048) * 1024 )); then
    echo "BLOCKED: insufficient host memory for VM $id plus 2 GiB reserve." >&2
    return 1
  fi
  echo "RAM gate: ${requested_mib} MiB for VM $id + 2048 MiB host reserve OK."
}

# qm guest exec prints a JSON result. Its process exit code alone is not
# sufficient: the command INSIDE the guest might have failed.
guest_exec() {
  local vm="$1" result
  shift
  if ! result="$(qm guest exec "$vm" --timeout 240 -- "$@")"; then
    echo "ERROR: guest command invocation failed on VM $vm." >&2
    return 1
  fi
  printf '%s\n' "$result" | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)
    sys.stdout.write(r.get("out-data", ""))
    sys.stderr.write(r.get("err-data", ""))
    if r.get("exited") != 1 or r.get("exitcode") != 0:
        sys.stderr.write("ERROR: guest command failed or did not exit.\n")
        sys.exit(1)
except (ValueError, TypeError) as e:
    sys.stderr.write(f"ERROR: invalid guest agent response: {e}\n")
    sys.exit(1)
'
}

wait_stopped() {
  local id="$1" i current
  for ((i=0; i<48; i++)); do
    current="$(state "$id")" || return 1
    [[ "$current" == stopped ]] && return 0
    sleep 5
  done
  echo "ERROR: VM $id did not stop within the timeout." >&2
  return 1
}

wait_agent() {
  local id="$1" i
  for ((i=0; i<30; i++)); do
    if qm agent "$id" ping >/dev/null 2>&1; then return 0; fi
    sleep 5
  done
  echo "ERROR: guest agent VM $id was not ready in time." >&2
  return 1
}

# Only a successful guest stop + graceful ACPI shutdown is acceptable for
# Minecraft. No 'qm stop' force action anywhere in this controller.
stop_source() {
  local id="$1"
  if [[ "$id" == 105 ]]; then
    echo 'Stopping Minecraft via Docker Compose ...'
    guest_exec 105 /bin/sh -c \
      'cd /home/debian/services/gtnh && docker compose stop --timeout 180' || return 1
  fi
  echo "Requesting graceful shutdown VM $id ..."
  qm shutdown "$id" --timeout 240 || return 1
  wait_stopped "$id"
}

# Shutdown is a best-effort response if Minecraft boot/health fails. Never
# force power off the guest or auto-restart the previous VM.
quiesce_failed_target() {
  local id="$1"
  echo "ERROR: startup verification failed for VM $id. Attempting graceful shutdown." >&2
  if [[ "$id" == 105 ]] && qm agent 105 ping >/dev/null 2>&1; then
    guest_exec 105 /bin/sh -c \
      'cd /home/debian/services/gtnh && docker compose stop --timeout 180' || true
  fi
  qm shutdown "$id" --timeout 240 || true
  if ! wait_stopped "$id"; then
    echo "MANUAL ACTION REQUIRED: VM $id may still be running." >&2
  fi
}

start_target() {
  local id="$1" i current health
  echo "Starting VM $id ..."
  qm start "$id" || return 1

  for ((i=0; i<24; i++)); do
    current="$(state "$id")" || return 1
    [[ "$current" == running ]] && break
    sleep 5
  done
  if [[ "$current" != running ]]; then
    echo "ERROR: VM $id did not reach running state." >&2
    return 1
  fi

  if [[ "$id" == 103 ]]; then
    wait_agent 103 || return 1
    echo 'VM 103 guest agent ready. Inference service health has NOT been verified.'
    return 0
  fi

  wait_agent 105 || return 1
  thermal_gate || return 1
  echo 'Starting GTNH Docker Compose ...'
  guest_exec 105 /bin/sh -c \
    'cd /home/debian/services/gtnh && docker compose up -d' || return 1

  # GTNH modpack can take several minutes to initialize.
  for ((i=0; i<60; i++)); do
    thermal_gate || return 1
    health="$(guest_exec 105 /bin/sh -c \
      'docker inspect --format "{{.State.Health.Status}}" gtnh')" || return 1
    if [[ "$health" == healthy ]]; then
      echo 'GTNH Docker health: healthy'
      return 0
    fi
    if [[ "$health" == unhealthy ]]; then
      echo 'ERROR: GTNH health is unhealthy.' >&2
      return 1
    fi
    sleep 10
  done
  echo 'ERROR: GTNH did not become healthy within 10 minutes.' >&2
  return 1
}

# Parallel calls to the controller on the Proxmox host must not interleave.
if [[ "$action" == switch ]]; then
  exec 9>"${HOMELAB_LOCK_FILE:-/run/lock/homelab-workload-mode.lock}"
  flock -n 9 || { echo 'BLOCKED: another workload switch is in progress.' >&2; exit 1; }
fi

ai="$(state 103)"
gtnh="$(state 105)"
restore="$(state 905)"

echo '===== PVE01 ====='
hostname
echo '===== WORKLOADS ====='
printf '103 inference01: %s\n' "$ai"
printf '105 gtnh01:     %s\n' "$gtnh"
printf '905 restore:    %s\n' "$restore"
echo '===== TEMPERATURA ====='
sensors 2>/dev/null | grep -m1 'Package id 0:' || echo unavailable

[[ "$action" == status ]] && exit 0

echo
if [[ "$action" == plan ]]; then
  echo "===== DRY RUN: $mode ====="
else
  echo "===== SWITCH: $mode ====="
fi

if [[ "$ai" == absent || "$gtnh" == absent ]]; then
  echo 'BLOCKED: main VM missing.'; exit 1
fi
if [[ "$restore" == running ]]; then
  echo 'BLOCKED: restore VM 905 is running.'; exit 1
fi
if [[ "$ai" == running && "$gtnh" == running ]]; then
  echo 'BLOCKED: AI and GTNH are running simultaneously.'; exit 1
fi
thermal_gate || exit 1

if [[ "$mode" == gtnh ]]; then
  source_id=103; source_state="$ai"
  target_id=105; target_state="$gtnh"
else
  source_id=105; source_state="$gtnh"
  target_id=103; target_state="$ai"
fi

if [[ "$action" == plan ]]; then
  if [[ "$source_state" == running ]]; then
    [[ "$source_id" == 105 ]] && echo '1. Stop Minecraft gracefully and save the world.'
    echo "2. Request graceful shutdown of VM $source_id."
    echo "3. Confirm that VM $source_id is stopped."
  else
    echo "Source VM $source_id is already stopped."
  fi
  if [[ "$target_state" == stopped ]]; then
    echo '4. Re-check thermal and resource preconditions before any start.'
    echo "5. Start VM $target_id."
    echo '6. Verify VM and workload health.'
  else
    echo "Target VM $target_id is already running."
  fi
  echo 'DRY RUN: no changes made.'
  exit 0
fi

if [[ "$source_state" == running ]]; then
  stop_source "$source_id" || {
    echo "BLOCKED: VM $source_id did not shut down safely. Target unchanged." >&2
    exit 1
  }
fi

# Check after source has stopped; any failure leaves it stopped (no rollback).
[[ "$(state "$source_id")" == stopped ]] || {
  echo 'BLOCKED: source VM is not stopped.' >&2; exit 1;
}
[[ "$(state 905)" != running ]] || {
  echo 'BLOCKED: restore VM 905 became active.' >&2; exit 1;
}
thermal_gate || exit 1
if [[ "$target_state" == stopped ]]; then
  memory_gate "$target_id" || exit 1
fi

if [[ "$target_state" == running ]]; then
  echo "VM $target_id was already running; no action needed."
  exit 0
fi

# A failed start may leave the target running: handle separately.
if ! start_target "$target_id"; then
  if [[ "$(state "$target_id")" == running ]]; then
    quiesce_failed_target "$target_id"
  fi
  echo "ERROR: failed to switch to $mode. Source remains off; inspect target." >&2
  exit 1
fi

echo "SUCCESS: switched to $mode."
REMOTE
