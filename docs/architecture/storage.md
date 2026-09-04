# Storage Architecture

## Purpose

This document describes the current storage layout, storage roles, monitoring
strategy and failure-domain boundaries.

## Physical layout

`pve01` currently contains two primary storage devices:

```text
pve01
 |
 +-- SSD ~512 GB
 |    |
 |    +-- Proxmox OS
 |    +-- local
 |    +-- local-lvm
 |
 +-- HDD ~1 TB
      |
      +-- ext4
      +-- hdd-backup
```

## Primary SSD

Model:

`P3-512`

Approximate capacity:

512 GB

Primary roles:

- Proxmox operating system;
- root filesystem;
- local storage;
- LXC storage;
- VM storage;
- `local-lvm`.

## LVM layout

Current approximate layout:

| Resource | Size |
|---|---:|
| Root | 64 GB |
| Swap | 8 GB |
| local-lvm / pve-data | ~334 GB |
| VG free reserve | ~68 GB |

The free volume-group capacity is intentionally retained rather than
allocating all storage immediately.

## LVM monitoring

A custom Node Exporter textfile collector exposes LVM thin-pool metrics.

Current metrics include:

- thin-pool data percentage;
- thin-pool metadata percentage;
- thin-pool total size;
- collector execution success;
- collector last-run timestamp.

Current monitored thin pool:

```text
VG: pve
LV: data
```

The collector executes through a systemd timer.

## Backup HDD

Model:

`ST1000DM010-2EP102`

Approximate capacity:

1 TB

Filesystem:

ext4

Filesystem label:

`pve-backup`

Mount point:

```text
/mnt/pve/hdd-backup
```

Proxmox storage ID:

```text
hdd-backup
```

Current primary role:

Proxmox backup storage.

Supported storage content also includes:

- backup;
- ISO;
- container templates;
- snippets.

## Stable device identity

Storage monitoring does not rely only on Linux device paths such as:

```text
/dev/sda
/dev/sdb
```

because enumeration order may change.

SMART monitoring identifies devices through hardware model information.

Current expected hardware models:

```text
P3-512
ST1000DM010-2EP102
```

This avoids binding monitoring semantics to unstable `/dev/sdX` names.

## SMART monitoring

`smartmontools` is installed directly on `pve01`.

A custom SMART collector exposes physical storage health through the Node
Exporter textfile collector.

Metrics currently include:

- SMART overall health;
- temperature;
- power-on hours;
- reallocated sectors;
- reported uncorrectable errors;
- pending sectors;
- offline uncorrectable sectors;
- CRC errors;
- collector execution status;
- collector freshness.

## Current SMART baseline

### Backup HDD

Health:

PASSED

Current critical counters:

```text
Reallocated sectors:       0
Pending sectors:           0
Offline uncorrectable:     0
CRC errors:                0
```

Historical observation:

```text
Reported_Uncorrectable = 2
```

Because this value represents historical state, alerting focuses on changes
rather than permanently alerting on the absolute historical counter.

### Primary SSD

Health:

PASSED

No current critical SMART indicators have been observed.

## Filesystem monitoring

The following mount points are explicitly monitored:

```text
/
```

and:

```text
/mnt/pve/hdd-backup
```

This ensures the backup filesystem remains visible to Prometheus even though
Node Exporter filesystem filtering is explicitly configured.

## Failure boundaries

The SSD and HDD are physically separate storage devices.

This protects against some device-level failures.

Example:

```text
SSD failure
   |
   +-- running workload may be lost
   |
   +-- HDD backup may remain available
```

However:

```text
pve01 physical loss
       |
       +-- SSD unavailable
       +-- HDD unavailable
```

Therefore the current HDD is not considered an independent backup failure
domain.

## Capacity monitoring

Current storage capacity monitoring covers:

- root filesystem;
- backup filesystem;
- LVM thin-pool data;
- LVM thin-pool metadata.

The objective is to detect capacity exhaustion before it affects workloads.

## Current storage risk

The largest storage reliability limitation is not the lack of a second disk.

The largest limitation is that both disks remain inside the same physical
host.

The platform therefore has storage separation, but not host-level backup
separation.

## Future storage direction

Next required reliability improvement:

**physically independent backup storage**

Target topology:

```text
pve01
 |
 +-- local workload storage
 |
 +-- local backup
 |
 +------ network ------> backup01
                         independent storage
```

Possible future implementation options include:

- Proxmox Backup Server;
- NAS;
- ZFS-backed storage;
- off-host backup replication;
- off-site replication;
- immutable backup copies.
