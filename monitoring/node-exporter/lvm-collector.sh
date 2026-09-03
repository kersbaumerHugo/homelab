#!/usr/bin/env bash
set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/prometheus/node-exporter}"
OUTPUT="$TEXTFILE_DIR/homelab_lvm.prom"

mkdir -p "$TEXTFILE_DIR"

TMP="$(mktemp "$TEXTFILE_DIR/.homelab_lvm.prom.XXXXXX")"

cleanup() {
    rm -f "$TMP"
}
trap cleanup EXIT

trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

write_failure() {
    cat > "$TMP" <<'EOF'
# HELP homelab_lvm_collector_success Whether the LVM collector completed successfully.
# TYPE homelab_lvm_collector_success gauge
homelab_lvm_collector_success 0
EOF
    chmod 0644 "$TMP"
    mv "$TMP" "$OUTPUT"
}

if ! LVS_OUTPUT="$(
    lvs \
        --units b \
        --nosuffix \
        --noheadings \
        --separator '|' \
        -o vg_name,lv_name,lv_attr,lv_size,data_percent,metadata_percent
)"; then
    write_failure
    exit 1
fi

cat > "$TMP" <<'EOF'
# HELP homelab_lvm_thin_data_percent Percentage of thin pool data space used.
# TYPE homelab_lvm_thin_data_percent gauge
# HELP homelab_lvm_thin_metadata_percent Percentage of thin pool metadata space used.
# TYPE homelab_lvm_thin_metadata_percent gauge
# HELP homelab_lvm_thin_size_bytes Thin pool total size in bytes.
# TYPE homelab_lvm_thin_size_bytes gauge
# HELP homelab_lvm_collector_success Whether the LVM collector completed successfully.
# TYPE homelab_lvm_collector_success gauge
# HELP homelab_lvm_collector_last_run_unixtime Unix time of the latest collector run.
# TYPE homelab_lvm_collector_last_run_unixtime gauge
EOF

FOUND=0

while IFS='|' read -r vg lv attr size data_percent metadata_percent; do
    vg="$(trim "$vg")"
    lv="$(trim "$lv")"
    attr="$(trim "$attr")"
    size="$(trim "$size")"
    data_percent="$(trim "$data_percent")"
    metadata_percent="$(trim "$metadata_percent")"

    # Thin-pool LV attributes start with "t".
    [[ "$attr" == t* ]] || continue

    FOUND=1

    printf 'homelab_lvm_thin_data_percent{vg="%s",lv="%s"} %s\n' \
    "$vg" "$lv" "$data_percent"

    printf 'homelab_lvm_thin_metadata_percent{vg="%s",lv="%s"} %s\n' \
    "$vg" "$lv" "$metadata_percent"

    printf 'homelab_lvm_thin_size_bytes{vg="%s",lv="%s"} %s\n' \
    "$vg" "$lv" "$size"

done <<< "$LVS_OUTPUT" >> "$TMP"

if (( FOUND == 0 )); then
    write_failure
    exit 1
fi

{
    printf 'homelab_lvm_collector_success 1\n'
    printf 'homelab_lvm_collector_last_run_unixtime %s\n' "$(date +%s)"
} >> "$TMP"

chmod 0644 "$TMP"
mv "$TMP" "$OUTPUT"
