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

state() {
  local result
  if ! result="$(qm status "$1" 2>/dev/null)"; then
    echo absent
    return
  fi

  case "$result" in
    "status: running"|"status: stopped")
      echo "${result#status: }"
      ;;
    *)
      echo "Unexpected VM state: $result" >&2
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
sensors | grep -m1 'Package id 0' || true

[[ "$action" == status ]] && exit 0

echo
echo "===== DRY RUN: $mode ====="

if [[ "$ai" == absent || "$gtnh" == absent ]]; then
  echo "BLOCKED: VM principal ausente."
  exit 1
fi

if [[ "$restore" == running ]]; then
  echo "BLOCKED: VM 905 de restauração está ligada."
  exit 1
fi

if [[ "$ai" == running && "$gtnh" == running ]]; then
  echo "BLOCKED: IA e GTNH estão ligados simultaneamente."
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
    echo "1. Parar Minecraft graciosamente e salvar o mundo."
  fi

  echo "2. Solicitar shutdown da VM $source_id."
  echo "3. Aguardar confirmação de VM desligada."
else
  echo "Origem VM $source_id já está desligada."
fi

if [[ "$target_state" == stopped ]]; then
  echo "4. Verificar pré-condições térmicas e de recursos."
  echo "5. Iniciar VM $target_id."
  echo "6. Verificar inicialização e saúde da workload."
else
  echo "Destino VM $target_id já está ligado."
fi

echo
echo "DRY RUN: nenhuma alteração realizada."
REMOTE
