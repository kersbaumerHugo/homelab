# Homelab Documentation

This directory is the documentation entry point for the homelab.

The Git repository is the source of truth for non-secret infrastructure
desired state. Documentation explains the architecture, operational state,
decisions, recovery procedures and known risks around that state.

## Documentation map

### Architecture

[Architecture index](architecture/README.md)

Documents:

- [Architecture overview](architecture/overview.md)
- [Network architecture](architecture/network.md)
- [Compute architecture](architecture/compute.md)
- [Storage architecture](architecture/storage.md)
- [Observability architecture](architecture/observability.md)
- [Backup and recovery architecture](architecture/backup-and-recovery.md)

### Operations

[Operations index](operations/README.md)

Documents:

- [Current platform state](operations/current-state.md)
- [Reliability posture](operations/reliability.md)
- [Security posture](operations/security.md)
- [Known risks](operations/known-risks.md)
- [Platform roadmap](operations/roadmap.md)

### Runbooks

[Runbook index](runbooks/README.md)

Current runbooks:

- [Platform boot and shutdown](runbooks/boot-and-shutdown.md)
- [Monitoring deployment](runbooks/monitoring-deploy.md)
- [Monitoring rollback](runbooks/monitoring-rollback.md)
- [mon01 backup and restore](runbooks/mon01-backup-restore.md)
- [Troubleshooting](runbooks/troubleshooting.md)
- [Disaster recovery](runbooks/disaster-recovery.md)

### Architecture Decision Records

[ADR index](adr/README.md)

Current ADRs:

- ADR 0001 - Disable OpenIPMI on pve01
- ADR 0002 - Use Git as the source of truth
- ADR 0003 - Run the monitoring stack in mon01
- ADR 0004 - Use Prometheus, Grafana and ntfy for observability
- ADR 0005 - Use local Proxmox vzdump backups for mon01
- ADR 0006 - Manage guest startup ordering explicitly
- ADR 0007 - Defer off-host backup until a second physical system exists

### Inventory

[Inventory index](../inventory/README.md)

Current inventory:

- OPNsense
- pve01
- mon01

## Documentation status

See:

[Documentation status](documentation-status.md)

This document defines which areas are documented, which are tested, and what
must be updated when the platform changes.

## Documentation principles

Documentation should:

- describe the system as it actually exists;
- distinguish current state from future plans;
- distinguish tested recovery from theoretical recovery;
- identify known limitations explicitly;
- contain no credentials or secrets;
- reference versioned configuration whenever possible;
- evolve together with infrastructure changes.

## Documentation ownership model

Every infrastructure change should answer:

```text
Does this change architecture?
Does this change operations?
Does this change recovery?
Does this change risk?
Does this change inventory?
Does this introduce a long-lived decision?
```

If the answer is yes, the corresponding document should be updated in the
same change.

## Baseline

Current documented baseline:

**2026-09-04**
