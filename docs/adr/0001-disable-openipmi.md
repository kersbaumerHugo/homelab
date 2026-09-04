# ADR 0001 - Disable OpenIPMI on pve01

## Status
Accepted

## Context
pve01 does not expose an IPMI/BMC device.
OpenIPMI fails during boot because no `/dev/ipmi*` device exists.

## Decision
Disable `openipmi.service` on pve01.

## Validation
- No IPMI device detected
- Proxmox management is unaffected
- `systemctl --failed` returns zero failed units
