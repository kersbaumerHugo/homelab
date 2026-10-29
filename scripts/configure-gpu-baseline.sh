#!/usr/bin/env bash
set -euo pipefail

GPU="${GPU_INDEX:-0}"
POWER_LIMIT_W="${GPU_POWER_LIMIT_W:-100}"

for _ in {1..30}; do
    if /usr/bin/nvidia-smi -i "$GPU" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

/usr/bin/nvidia-smi -i "$GPU" >/dev/null

/usr/bin/nvidia-smi \
    -i "$GPU" \
    -pm 1 \
    >/dev/null

/usr/bin/nvidia-smi \
    -i "$GPU" \
    -pl "$POWER_LIMIT_W" \
    >/dev/null

read -r current_limit persistence_mode < <(
    /usr/bin/nvidia-smi \
        -i "$GPU" \
        --query-gpu=power.limit,persistence_mode \
        --format=csv,noheader,nounits \
        | awk -F', ' '{print $1, $2}'
)

if [[ "$persistence_mode" != "Enabled" ]]; then
    echo "GPU persistence mode verification failed." >&2
    exit 1
fi

if ! awk \
    -v current="$current_limit" \
    -v expected="$POWER_LIMIT_W" \
    'BEGIN { exit !((current + 0) == (expected + 0)) }'
then
    echo \
        "GPU power limit verification failed: expected=${POWER_LIMIT_W}W current=${current_limit}W" \
        >&2
    exit 1
fi

echo "GPU baseline applied: persistence=Enabled power_limit=${current_limit}W"
