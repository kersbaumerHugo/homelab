# ADR 0007 - Defer Off-host Backup Until a Second Physical System Exists

## Status

Accepted risk / deferred implementation

## Date

2026-09-04

## Context

The current backup architecture stores `mon01` backups on a separate HDD, but
the HDD remains inside `pve01`.

A true off-host backup requires another independent physical failure domain.

No second suitable physical system or independent network storage currently
exists.

Deploying Proxmox Backup Server as a guest inside `pve01` would add backup
features but would not solve the physical failure-domain problem.

## Decision

Do not claim or implement pseudo off-host backup inside `pve01`.

Keep the current local backup layer and explicitly defer off-host backup until
a second physical system is available.

## Current accepted risk

Complete physical loss of `pve01` may cause simultaneous loss of:

- running workloads;
- primary SSD;
- local backup HDD;
- monitoring platform.

This risk is documented as critical.

## Exit criterion

This ADR can be superseded when an independent system exists with:

- separate physical hardware;
- independent storage;
- network connectivity to pve01;
- sufficient capacity for protected workloads.

Preferred initial role:

```text
backup01
  |
Proxmox Backup Server
```

## Required validation after implementation

The future off-host backup layer is not complete until:

- backup replication succeeds;
- remote freshness is monitored;
- restore from the remote copy is tested;
- retention is documented;
- loss of the local backup does not remove the remote copy.

## Consequences

### Positive

- avoids false confidence;
- keeps failure-domain semantics explicit;
- prevents unnecessary complexity that does not reduce the actual risk.

### Negative

- complete host loss remains a critical open risk;
- the platform is not yet aligned with a full 3-2-1 backup strategy.
