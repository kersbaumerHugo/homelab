# Backup and Recovery Architecture

## Purpose

The backup platform exists to provide recoverability rather than simply to
create backup files.

A backup is considered meaningful only if:

- it is created successfully;
- it remains available;
- its state is monitored;
- its configuration is reproducible;
- restore has been tested.

## Current protected workload

Current protected workload:

```text
CT 100
mon01
```

## Backup flow

```text
mon01
  |
  | Proxmox vzdump
  v
snapshot
  |
  | zstd
  v
compressed archive
  |
  v
hdd-backup
/mnt/pve/hdd-backup/dump
```

## Backup job

Job ID:

```text
mon01-daily
```

Schedule:

```text
03:00
```

Mode:

```text
snapshot
```

Compression:

```text
zstd
```

Storage:

```text
hdd-backup
```

## Retention

Current policy:

```text
daily:   7
weekly:  4
monthly: 3
```

## Desired state

The backup policy is versioned under:

```text
proxmox/pve01/backup-jobs/mon01-daily.yml
```

Runtime configuration is applied using:

```text
scripts/deploy-backup-jobs.sh
```

The deployment logic is idempotent.

If the job already exists, it is updated.

If the job does not exist, it is created.

## Drift detection

Runtime backup configuration is compared against Git desired state.

Drift testing has been performed by manually changing the backup schedule.

Example:

```text
Git
03:00
  |
runtime manually changed
04:00
  |
verification
FAIL - drift detected
  |
deployment
  |
runtime reconciled to 03:00
```

## Reconstruction test

The backup job has also been deliberately deleted from Proxmox.

The job was successfully reconstructed using only the versioned configuration
and deployment tooling.

This demonstrates that the backup job itself is reproducible.

## Backup monitoring

A custom collector monitors backup state.

Current metrics include:

- backup job presence;
- backup job enabled state;
- backup artifact presence;
- latest backup timestamp;
- latest backup size;
- collector execution state;
- collector freshness.

The backup identity metric label is:

```text
backup_job
```

rather than Prometheus' scrape label:

```text
job
```

This avoids label collisions.

## Backup freshness objective

Current local backup freshness threshold:

```text
26 hours
```

This gives additional time around the nominal daily schedule while still
detecting missed backups promptly.

## Alerts

Current backup alerts include:

- collector failed;
- collector stale;
- backup job missing;
- backup job disabled;
- backup artifact missing;
- backup older than 26 hours.

Backup alerts are routed through:

```text
Grafana
   |
ntfy-homelab
   |
homelab-alerts
```

## Failure injection

Backup alerting has been tested through deliberate backup job disablement.

Validated chain:

```text
backup job enabled = 0
          |
          v
backup collector
          |
          v
Node Exporter
          |
          v
Prometheus
          |
          v
Grafana
          |
      Pending
          |
       Firing
          |
          v
ntfy notification
```

Recovery was performed through the Git-controlled deployment script rather
than through an ad-hoc manual correction.

## Restore test

A real backup artifact was restored into temporary container:

```text
CT 900
```

The restored system was isolated from the production container before startup.

Validated after restore:

- container startup;
- hostname change;
- DHCP;
- network addressing;
- default route;
- gateway reachability;
- Internet access;
- DNS resolution;
- Prometheus;
- Grafana;
- ntfy;
- monitoring configuration files.

After validation:

```text
CT 900 stopped
CT 900 destroyed
```

The restore drill was successful.

## Current recovery capability

Current recovery path for loss of `mon01`:

```text
mon01 unavailable
       |
       v
identify latest vzdump
       |
       v
restore container
       |
       v
validate networking
       |
       v
validate services
       |
       v
return service
```

Detailed operational procedures belong under:

```text
docs/runbooks/
```

## Current backup failure domain

Current backup storage remains inside `pve01`.

```text
+--------------------- pve01 ---------------------+
|                                                 |
| SSD                       HDD                   |
| workloads                 backups               |
|                                                 |
+-------------------------------------------------+
```

This protects against several logical and device-level failures, but it does
not protect against complete physical loss of `pve01`.

Therefore:

**the current backup is local, not off-host.**

## Initial recovery objectives

Current working objectives:

```text
RPO target: <= 24 hours
RTO target: <= 2 hours
```

These values are initial operational targets and may be refined as the
platform evolves.

## Next major milestone

The next required backup architecture is:

```text
pve01
  |
local backup
  |
network replication
  |
backup01
independent physical system
```

Potential implementation:

Proxmox Backup Server.

This milestone is currently blocked by the lack of a second physical system.

## Long-term direction

Target architecture:

```text
production
    |
local backup
    |
off-host backup
    |
off-site copy
```

The long-term objective is a practical implementation of the 3-2-1 backup
principle.
