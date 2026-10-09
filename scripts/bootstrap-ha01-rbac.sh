#!/usr/bin/env bash
set -euo pipefail

USER_ID="opentofu@pve"
TOKEN_ID="opentofu@pve!ha01-deploy"

VM_PRIVS="VM.Allocate VM.Audit VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network VM.Config.HWType VM.Config.Options VM.PowerMgmt"

STORAGE_PRIVS="Datastore.Audit Datastore.AllocateSpace Datastore.AllocateTemplate"

# Management of the HA VM.
pveum role add HomelabHaVm --privs "$VM_PRIVS" 2>/dev/null || \
  pveum role modify HomelabHaVm --privs "$VM_PRIVS"

# Network bridge access.
pveum role add HomelabHaNetwork --privs "SDN.Use" 2>/dev/null || \
  pveum role modify HomelabHaNetwork --privs "SDN.Use"

# Image upload and virtual disk allocation.
pveum role add HomelabHaStorage --privs "$STORAGE_PRIVS" 2>/dev/null || \
  pveum role modify HomelabHaStorage --privs "$STORAGE_PRIVS"

for IDENTITY in "$USER_ID" "$TOKEN_ID"; do
  if [[ "$IDENTITY" == *"!"* ]]; then
    SUBJECT=(--tokens "$IDENTITY")
  else
    SUBJECT=(--users "$IDENTITY")
  fi

  pveum acl modify /vms/104 \
    "${SUBJECT[@]}" --roles HomelabHaVm

  pveum acl modify /sdn/zones/localnetwork/vmbr0 \
    "${SUBJECT[@]}" --roles HomelabHaNetwork \
    --propagate 0

  pveum acl modify /storage/local \
    "${SUBJECT[@]}" --roles HomelabHaStorage

  pveum acl modify /storage/local-lvm \
    "${SUBJECT[@]}" --roles HomelabHaStorage
done

echo "=== TOKEN EFFECTIVE PERMISSIONS ==="
pveum user token permissions opentofu@pve ha01-deploy
