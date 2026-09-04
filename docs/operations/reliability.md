# Reliability Posture

## Purpose

This document describes the current reliability model of the homelab.

The objective is not to claim high availability where it does not exist.
Instead, the platform documents which failure modes are currently tolerated,
which recovery procedures have been tested, and which risks remain open.

## Reliability principles

The current platform follows these principles:

- backups must be restorable, not merely present;
- important runtime state should be reproducible from Git;
- configuration drift should be detectable;
- infrastructure changes should be validated before deployment;
- deployment failures should roll back when possible;
- monitoring should verify both service health and infrastructure health;
- known single points of failure must be documented explicitly;
- failure scenarios should be tested deliberately when safe.

## Current service model

The platform currently has one primary compute failure domain:

```text
pve01
 |
 +-- mon01
 |    |
 |    +-- Prometheus
 |    +-- Grafana
 |    +-- ntfy
 |
 +-- local-lvm
 |
 +-- hdd-backup
```

This means the platform is currently designed for recoverability rather than
high availability.

## Current reliability controls

### Configuration reproducibility

Non-secret desired state is stored in Git.

Examples include:

- monitoring configuration;
- Grafana provisioning;
- custom metric collectors;
- Proxmox guest startup policy;
- Proxmox backup job policy.

Manual runtime changes are treated as drift unless they are intentionally
reconciled back into Git.

### Validation before deployment

Monitoring changes are validated before deployment.

Current validation includes:

- YAML parsing;
- Grafana alert-state validation;
- Node Exporter configuration checks;
- Python syntax validation;
- systemd unit validation;
- Grafana dashboard JSON validation;
- ShellCheck;
- Prometheus configuration validation;
- duplicate Grafana UID detection;
- datasource UID validation.

### Transactional monitoring deployment

Monitoring deployment uses:

```text
scripts/deploy-monitoring.sh
```

The deployment flow includes:

```text
validation
    |
candidate upload
    |
runtime backup
    |
deployment
    |
health verification
```

If deployment fails after changes begin, the deployment process attempts to
restore the previous configuration.

A rollback drill has been executed successfully.

### Runtime verification

Runtime health and Git-to-runtime synchronization are checked through:

```text
scripts/verify-monitoring.sh
```

The script currently verifies:

- pve01 connectivity;
- mon01 runtime state;
- host services;
- monitoring services;
- health endpoints;
- Prometheus target availability;
- required infrastructure metrics;
- backup state;
- guest boot policy;
- systemd health;
- Proxmox storage state;
- SMART health;
- Grafana provisioning sanity;
- Git-to-runtime drift.

### Guest startup recovery

mon01 is configured to start automatically with pve01.

Current policy:

```text
onboot = true
order = 10
startup delay = 30 seconds
shutdown timeout = 60 seconds
```

A complete host reboot has been tested.

After the reboot:

- mon01 started automatically;
- Prometheus became active;
- Grafana became active;
- ntfy became active.

### Graceful shutdown

The repository includes:

```text
scripts/shutdown-homelab.sh
```

The script requests a graceful Proxmox host shutdown so guest lifecycle is
managed through Proxmox rather than force-stopping workloads directly.

### Local backup

mon01 is protected by a scheduled Proxmox backup.

Current policy:

```text
job: mon01-daily
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

### Backup reproducibility

The backup policy is versioned in Git.

The deployment tooling can:

- create the job if it does not exist;
- update the job if it exists;
- restore the expected configuration after drift.

The job has been intentionally deleted and successfully reconstructed from
Git.

### Backup restore validation

A real mon01 backup artifact has been restored into temporary CT 900.

Validated after restore:

- boot;
- network connectivity;
- routing;
- DNS;
- Prometheus;
- Grafana;
- ntfy;
- monitoring configuration.

The temporary test container was destroyed after validation.

### Backup observability

Backup monitoring verifies:

- backup job presence;
- backup job enabled state;
- backup artifact presence;
- last backup timestamp;
- last backup size;
- collector execution health;
- collector freshness.

Backup alerting has been validated using deliberate failure injection.

## Tested failure and recovery scenarios

The following scenarios have been tested successfully:

| Scenario | Result |
|---|---|
| pve01 reboot | Recovered |
| mon01 automatic startup | Validated |
| monitoring deployment | Validated |
| monitoring rollback | Validated |
| LVM metric collection | Validated |
| SMART metric collection | Validated |
| backup creation | Validated |
| mon01 restore from backup | Validated |
| backup job deletion | Reconstructed from Git |
| backup schedule drift | Detected |
| backup policy reconciliation | Validated |
| backup job disablement | Alerted |
| ntfy delivery | Validated |

## Recovery objectives

Current working objectives:

```text
RPO target: <= 24 hours
RTO target: <= 2 hours
```

These values are initial engineering targets rather than formal production
SLAs.

They should be revisited as new workloads are introduced.

## Current single points of failure

### pve01

Loss of pve01 removes:

- compute;
- mon01;
- Prometheus;
- Grafana;
- ntfy;
- current local backup access.

### OPNsense

Loss of the firewall removes the current network gateway.

### Ethernet switch

Loss of the switch interrupts LAN connectivity.

### Monitoring failure domain

The system that monitors pve01 is itself hosted on pve01.

Therefore complete host loss cannot currently be reliably alerted from inside
the platform.

## Current resilience boundary

The platform currently provides useful protection against:

- application/container corruption;
- some configuration mistakes;
- monitoring configuration failures;
- backup job configuration drift;
- primary SSD failure, assuming the backup HDD remains healthy;
- selected storage degradation conditions.

The platform does not currently provide protection against:

- complete pve01 physical loss;
- theft or fire affecting the host;
- simultaneous loss of SSD and HDD;
- complete LAN failure;
- OPNsense hardware failure;
- site-wide power loss without external protection.

## Reliability maturity status

Current state:

```text
Reproducibility        GOOD
Runtime verification   GOOD
Local backup           GOOD
Restore validation     GOOD
Monitoring             GOOD
Failure injection      PARTIAL
Host redundancy        NONE
Off-host backup        NONE
Off-site backup        NONE
External monitoring    NONE
Power redundancy       NONE
```

## Next reliability milestone

The highest-priority reliability improvement is:

**create a second physical failure domain**

The preferred initial use for that system is off-host backup, potentially
using Proxmox Backup Server.

After that, the next reliability priorities are:

1. external host-down monitoring;
2. off-site backup;
3. periodic automated restore drills;
4. power protection;
5. additional compute capacity and service separation.
