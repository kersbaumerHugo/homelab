# Architecture Documentation

This directory documents how the homelab is designed.

Architecture documents describe system structure and interactions. They should
not be used as step-by-step operating procedures.

## Documents

### [Overview](overview.md)

High-level view of:

- physical topology;
- compute;
- storage;
- observability;
- configuration flow;
- backup architecture;
- failure domains.

### [Network](network.md)

Covers:

- LAN topology;
- addressing;
- OPNsense;
- routing;
- infrastructure addresses;
- network dependencies;
- current network limitations.

### [Compute](compute.md)

Covers:

- pve01 hardware;
- Proxmox responsibilities;
- mon01;
- startup ordering;
- shutdown orchestration;
- thermal limitations;
- compute failure domain.

### [Storage](storage.md)

Covers:

- SSD and HDD roles;
- LVM layout;
- SMART monitoring;
- filesystem monitoring;
- storage failure boundaries.

### [Observability](observability.md)

Covers:

- Prometheus;
- Grafana;
- ntfy;
- Node Exporter;
- custom collectors;
- deployment and verification;
- monitoring failure domain.

### [Backup and Recovery](backup-and-recovery.md)

Covers:

- local backup architecture;
- backup job policy;
- retention;
- backup monitoring;
- restore validation;
- current RPO/RTO;
- off-host backup limitation.

## Architecture rules

Architecture documents should be updated when:

- a physical node is added or removed;
- network topology changes;
- storage roles change;
- a foundational service moves between hosts;
- a failure domain changes;
- a new control plane or orchestration layer is introduced.

Long-lived architectural choices should also be recorded as ADRs.
