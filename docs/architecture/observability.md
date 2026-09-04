# Observability Architecture

## Purpose

The observability platform is designed to answer two primary questions:

1. Is the platform healthy?
2. If something fails, where should investigation begin?

The current stack provides metrics, dashboards, alerts, notifications and
runtime verification.

## Architecture

```text
                        pve01
                          |
             +------------+------------+
             |                         |
       node_exporter                systemd
             |
             +-- native collectors
             |     |
             |     +-- CPU
             |     +-- memory
             |     +-- filesystem
             |     +-- hwmon
             |
             +-- textfile collector
                   |
                   +-- LVM collector
                   +-- SMART collector
                   +-- backup collector
                          |
                          v
                       :9100
                          |
                          v
                       mon01
                          |
                     Prometheus
                          |
                          v
                       Grafana
                          |
                          v
                         ntfy
```

## Prometheus

Prometheus runs inside `mon01`.

Primary `pve01` target:

```text
192.168.10.10:9100
```

Current Prometheus scrape job:

```text
pve01
```

Prometheus provides:

- metric collection;
- metric storage;
- PromQL queries;
- the data source used by Grafana.

## Node Exporter

Node Exporter runs directly on `pve01`.

Native collectors currently provide:

- CPU metrics;
- memory metrics;
- filesystem metrics;
- hardware-monitoring metrics.

Filesystem collection explicitly includes:

```text
/
```

and:

```text
/mnt/pve/hdd-backup
```

## Textfile collector

The Node Exporter textfile collector provides the integration point for
custom infrastructure metrics.

Current custom collectors:

### LVM collector

Purpose:

Monitor thin-pool capacity and collector health.

### SMART collector

Purpose:

Monitor physical disk health and disk-related error indicators.

### Backup collector

Purpose:

Monitor backup job state, backup artifact state and backup freshness.

## Collector design

Custom collectors:

- execute independently from Node Exporter;
- write Prometheus text-format files;
- write output atomically;
- expose collector execution status;
- expose collector last-run timestamps;
- execute through systemd timers.

This separates data acquisition from metric serving.

## Grafana

Grafana runs inside `mon01`.

Grafana provides:

- dashboards;
- alert evaluation;
- alert grouping;
- notification routing.

Provisioning is stored in Git.

## Alert organization

Current folders:

```text
Homelab - Availability
Homelab - Memory
Homelab - Temperature
Homelab - Storage
Homelab - Monitoring
Homelab - Tests
```

Preferred provisioning convention:

```text
one alert rule = one provisioning file
```

This improves:

- reviewability;
- Git history;
- troubleshooting;
- alert ownership;
- rule-level change tracking.

## Alert coverage

### Availability

Infrastructure and service availability.

### Memory

Memory pressure and capacity risk.

### Temperature

CPU and disk thermal conditions.

### Storage

- filesystem capacity;
- LVM capacity;
- SMART health;
- disk error changes;
- backup state;
- backup freshness.

### Monitoring

Collector failures and stale telemetry.

## Notifications

ntfy is self-hosted inside `mon01`.

Current topic:

```text
homelab-alerts
```

Grafana contact point:

```text
ntfy-homelab
```

Alert delivery has been tested successfully.

## Monitoring deployment

Monitoring desired state is deployed using:

```text
scripts/deploy-monitoring.sh
```

The deployment flow is:

```text
repository
    |
validation
    |
candidate upload
    |
runtime backup
    |
deployment
    |
health checks
    |
success
```

If deployment fails after runtime changes begin:

```text
failure
   |
rollback
   |
previous configuration restored
```

## Repository validation

Repository validation is performed through:

```text
scripts/validate-monitoring.sh
```

Current validation includes:

- YAML parsing;
- Grafana alert-state validation;
- YAML tab checks;
- Node Exporter configuration checks;
- Python syntax validation;
- systemd unit validation;
- dashboard JSON validation;
- ShellCheck;
- Prometheus configuration validation;
- duplicate Grafana UID detection;
- datasource UID validation.

## Runtime verification

Runtime verification is performed through:

```text
scripts/verify-monitoring.sh
```

The verification process checks both infrastructure health and
Git-to-runtime synchronization.

Current verification includes:

- pve01 SSH connectivity;
- mon01 runtime state;
- host services;
- monitoring services;
- health endpoints;
- Prometheus target status;
- required metrics;
- backup health;
- boot policy;
- systemd health;
- Proxmox storage state;
- SMART health;
- Grafana provisioning sanity;
- Git-to-runtime drift.

## Failure injection

Several monitoring behaviors have been validated by creating controlled
failures.

Examples include:

- monitoring deployment rollback;
- backup job deletion;
- backup job disablement;
- backup configuration drift;
- Git-driven reconciliation.

Failure injection validates the full operational chain rather than only the
static configuration.

## Current observability limitation

The complete monitoring stack currently depends on `pve01`.

```text
pve01 fails
    |
    +-- mon01 fails
    +-- Prometheus fails
    +-- Grafana fails
    +-- ntfy fails
```

This means the platform cannot currently generate a reliable internal
notification for complete `pve01` loss.

Future architecture requires an out-of-band watcher on a different physical
system.

## Future observability direction

Possible future improvements include:

- external host-down monitoring;
- centralized logs with Loki;
- distributed tracing;
- black-box probing;
- SLO dashboards;
- synthetic checks;
- alert inhibition and dependency-aware routing;
- long-term metrics retention.
