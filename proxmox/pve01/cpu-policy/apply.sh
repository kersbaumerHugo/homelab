#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-apply}"
BASE="/sys/devices/system/cpu/cpufreq"

shopt -s nullglob
policies=("$BASE"/policy*)

((${#policies[@]} > 0)) || {
  echo "No CPU frequency policies found" >&2
  exit 1
}

case "$MODE" in
  apply)
    # Validate all policies before changing anything.
    for p in "${policies[@]}"; do
      [[ "$(<"$p/scaling_driver")" == "intel_pstate" ]]
      grep -qw balance_performance \
        "$p/energy_performance_available_preferences"
    done

    for p in "${policies[@]}"; do
      echo powersave > "$p/scaling_governor"
      echo balance_performance \
        > "$p/energy_performance_preference"
    done
    ;;

  verify)
    for p in "${policies[@]}"; do
      governor="$(<"$p/scaling_governor")"
      epp="$(<"$p/energy_performance_preference")"

      echo "$(basename "$p"): $governor / $epp"

      [[ "$governor" == "powersave" ]]
      [[ "$epp" == "balance_performance" ]]
    done
    ;;

  rollback)
    for p in "${policies[@]}"; do
      echo performance > "$p/scaling_governor"
    done
    ;;

  *)
    echo "Usage: $0 {apply|verify|rollback}" >&2
    exit 2
    ;;
esac
