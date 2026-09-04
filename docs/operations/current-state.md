# Current Platform State

Baseline date: **2026-09-04**

This document describes the actual operational state of the homelab.

It is intentionally different from a roadmap: only implemented or
explicitly known state belongs here.

## Network

Status: **Operational**

- OPNsense dedicated firewall
- LAN: `192.168.10.0/24`
- Gateway: `192.168.10.1`
- DHCP enabled
- DHCP range: `192.168.10.100-199`
- WAN operational
- LAN operational
- TOTP enabled for administrative access
- OPNsense configuration backup created

## pve01

Status: **Operational**

- Proxmox VE
- Management IP: `192.168.10.10`
- Intel Core i7-9700K
- 24 GiB DDR4
- Intel I219-V Ethernet
- UEFI
- VT-x enabled
- VT-d enabled
- Proxmox repositories configured for no-subscription usage
- failed systemd units currently monitored

### Known hardware limitations

The CPU cooling solution is currently inadequate for sustained heavy
CPU workloads.

Stress testing caused temperatures above 90 C and thermal throttling.

Sustained CPU-heavy workloads should therefore be avoided until the
cooling solution is replaced.

A temporary NVIDIA GT610 is currently installed for display purposes.

## Storage

Status: **Operational**

Primary SSD:

- approximately 512 GB
- Proxmox system storage
- `local`
- `local-lvm`
- approximately 68 GB LVM volume-group reserve

Backup HDD:

- approximately 1 TB
- ext4
- storage ID: `hdd-backup`
- approximately 916 GiB usable capacity

SMART long tests have completed successfully on both devices.

The HDD contains a historical non-zero reported-uncorrectable counter,
but currently has:

- 0 reallocated sectors
- 0 pending sectors
- 0 offline uncorrectable sectors
- 0 CRC errors

The monitoring design treats changes in relevant SMART counters as more
important than permanently alerting on historical counters.

## mon01

Status: **Operational**

- Proxmox LXC
- VMID: `100`
- hostname: `mon01`
- IP: `192.168.10.162`
- Debian 13
- unprivileged container
- 2 vCPU
- 4 GiB RAM
- 512 MiB swap
- 32 GB disk

Services:

- Prometheus
- Grafana
- ntfy

Startup:

- automatic startup enabled
- startup order: `10`
- startup delay: 30 seconds
- shutdown timeout: 60 seconds

A real pve01 reboot test confirmed that mon01 starts automatically and
that Prometheus, Grafana and ntfy become active without manual
intervention.

## Observability

Status: **Operational**

Host telemetry:

- Prometheus Node Exporter
- lm-sensors
- smartmontools
- filesystem collector
- hwmon collector
- textfile collector

Custom collectors:

- LVM collector
- SMART collector
- backup collector

All custom collectors are executed through systemd timers and expose
metrics through the Node Exporter textfile collector.

## Prometheus

Status: **Operational**

Prometheus runs inside mon01.

pve01 is scraped through:

`192.168.10.10:9100`

Metrics currently verified include:

- CPU temperature
- memory
- root filesystem
- backup filesystem
- LVM data usage
- LVM metadata usage
- SMART health
- disk temperature
- SMART counters
- backup state
- backup freshness

## Grafana

Status: **Operational**

Grafana runs inside mon01.

Provisioning is managed through Git.

Current alert folders:

```text
Homelab - Availability
Homelab - Memory
Homelab - Temperature
Homelab - Storage
Homelab - Monitoring
Homelab - Tests

Alerting follows the preferred convention:

one alert rule per provisioning file

Notifications

Status: Operational

ntfy runs inside mon01.

Current topic:

homelab-alerts

Grafana alert notifications have been tested successfully against ntfy.

Monitoring deployment

Status: Operational

Monitoring deployment is automated through:

scripts/deploy-monitoring.sh

The deployment process includes:

repository validation
candidate upload
configuration validation
runtime backup
deployment
health verification
automatic rollback on failure

A rollback drill has been performed successfully.

Runtime verification

Status: Operational

Runtime state is validated through:

scripts/verify-monitoring.sh

Verification includes:

SSH connectivity
mon01 state
host services
monitoring services
health endpoints
Prometheus target state
required metrics
backup health
boot policy
systemd health
Proxmox storage
SMART health
Grafana provisioning sanity
Git-to-runtime drift
CI

Status: Operational

GitHub Actions validates monitoring changes before merge.

Current validation includes:

YAML parsing
Grafana alert enum validation
tab detection
Node Exporter configuration
Python syntax
systemd units
Grafana dashboards
ShellCheck
Prometheus configuration
duplicate Grafana UIDs
datasource UIDs
Grafana provisioning integration tests
Backup

Status: Operational locally

Backup job:

mon01-daily

Target:

CT 100 / mon01

Configuration:

schedule: 03:00
mode: snapshot
compression: zstd
storage: hdd-backup

Retention:

daily: 7
weekly: 4
monthly: 3

Backup desired state is versioned in Git.

The deployment script can:

create the job when missing
update an existing job
reconcile configuration drift
Restore validation

Status: Tested successfully

A real mon01 backup was restored into temporary CT 900.

Validated after restore:

container boot
DHCP
routing
Internet connectivity
DNS
Prometheus
Grafana
ntfy
monitoring configuration files

The temporary restore container was subsequently stopped and destroyed.

This proves that the current mon01 backup is restorable.

Backup monitoring

Status: Operational

The backup collector exposes:

backup job presence
backup job enabled state
backup artifact presence
last backup timestamp
last backup size
collector execution state
collector freshness

Grafana alerts monitor backup failures.

A deliberate failure injection was performed by disabling the backup
job.

The complete detection path was validated:

backup job disabled
        |
backup collector
        |
Prometheus
        |
Grafana
        |
ntfy notification

The backup job was then reconciled using the Git-driven deployment
script.

Boot and shutdown

Status: Operational

mon01 automatic startup has been tested through a real pve01 reboot.

A graceful homelab shutdown script also exists:

scripts/shutdown-homelab.sh

The host shutdown relies on Proxmox guest orchestration rather than
force-stopping containers.

Successfully validated failure/recovery scenarios

The following scenarios have been tested:

pve01 reboot
mon01 automatic startup
Prometheus restart
Grafana restart
ntfy restart
monitoring deployment
monitoring rollback
LVM metric collection
SMART metric collection
backup creation
backup restore
backup job deletion
backup job reconstruction from Git
backup configuration drift
configuration reconciliation
backup monitoring
backup alert failure injection
ntfy alert delivery
Current risks
Critical architectural risk

There is currently only one physical compute failure domain.

Both the production SSD and local backup HDD are installed inside
pve01.

Complete loss of pve01 may therefore cause simultaneous loss of the
running workload and the local backup.

Monitoring failure domain

Prometheus, Grafana and ntfy all run inside mon01, which itself runs on
pve01.

A complete pve01 outage therefore also removes the current alerting
platform.

An external watcher will eventually be required for reliable host-down
notification.

Power

No UPS is currently part of the documented platform.

Cooling

The current CPU cooler is insufficient for sustained high CPU load.

Next major milestone

The next major reliability milestone is:

off-host backup

This requires a second physical system or storage target.

Until that hardware exists, additional backup replication work is
blocked by the absence of another physical failure domain.
