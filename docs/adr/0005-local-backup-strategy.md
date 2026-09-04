# ADR 0005 - Use Local Proxmox vzdump Backups for mon01

## Status

Accepted as an interim backup layer

## Date

2026-09-03

## Context

`mon01` contains the current monitoring platform and is foundational to the
homelab.

A recovery mechanism was required before adding more workloads.

The available hardware included:

- the primary SSD used by Proxmox and workloads;
- a physically separate 1 TB HDD inside `pve01`.

No second physical host was available.

## Decision

Protect `mon01` with a scheduled Proxmox `vzdump` backup stored on the
separate HDD.

Backup job:

```text
mon01-daily
```

Configuration:

```text
VMID: 100
schedule: 03:00
mode: snapshot
compression: zstd
storage: hdd-backup
```

Retention:

```text
daily: 7
weekly: 4
monthly: 3
```

The desired state is versioned in Git.

## Recovery objective

Initial engineering objectives:

```text
RPO <= 24 hours
RTO <= 2 hours
```

These are working objectives rather than formal production SLAs.

## Monitoring

Backup health must be observable.

Current monitoring includes:

- job presence;
- job enabled state;
- artifact presence;
- latest artifact timestamp;
- latest artifact size;
- collector health;
- collector freshness.

## Restore requirement

A backup is not considered validated until a real restore succeeds.

A real `mon01` backup was restored to temporary CT 900 and validated before
the temporary guest was destroyed.

## Consequences

### Positive

- protects against several workload and SSD-level failures;
- simple integration with Proxmox;
- fast local restore;
- policy is reproducible from Git;
- backup state can be monitored.

### Negative

The backup is not off-host.

Both the production SSD and backup HDD remain inside `pve01`.

Complete host loss can remove both production and backup simultaneously.

## Classification

The current backup is:

**local backup**

It must not be described as:

- off-host;
- off-site;
- fully independent.

## Future direction

The next backup milestone is a second physical system, preferably running
Proxmox Backup Server or an equivalent independent backup target.

## Revisit condition

Revisit this decision when a second physical failure domain becomes available.
