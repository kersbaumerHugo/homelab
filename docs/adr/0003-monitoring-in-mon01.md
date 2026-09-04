# ADR 0003 - Run the Monitoring Stack in mon01

## Status

Accepted with known limitation

## Date

2026-08-31

## Context

The homelab required an initial observability platform for:

- metrics collection;
- dashboards;
- alert evaluation;
- notifications;
- infrastructure troubleshooting.

The platform had one available compute host, `pve01`.

Running monitoring services directly on the Proxmox host would increase host
coupling and make the hypervisor responsible for application-level services.

A dedicated guest provides better separation and a clearer lifecycle.

## Decision

Run the primary monitoring stack in an unprivileged LXC container:

```text
CT 100
mon01
```

Current services:

- Prometheus;
- Grafana;
- ntfy.

Current resources:

- 2 vCPU;
- 4 GiB RAM;
- 512 MiB swap;
- 32 GB disk.

## Why LXC

LXC was selected because the monitoring workload:

- is Linux-native;
- does not currently require a full VM boundary;
- benefits from low overhead;
- can be backed up and restored through Proxmox;
- is easy to integrate into guest startup ordering.

## Security model

`mon01` is unprivileged.

Nesting is disabled because the current services do not require nested
container functionality.

## Startup

`mon01` is configured to start automatically after `pve01`.

Current startup order:

```text
order = 10
```

## Consequences

### Positive

- monitoring services are separated from the Proxmox host;
- the monitoring stack can be backed up as one guest;
- startup and shutdown can be orchestrated through Proxmox;
- the guest can be restored independently;
- the hypervisor remains relatively clean.

### Negative

The monitoring system still depends on the same physical host it monitors.

A complete `pve01` outage removes:

- `mon01`;
- Prometheus;
- Grafana;
- ntfy.

Therefore the current architecture cannot reliably alert on total host loss.

## Validation

The design has been validated through:

- real `pve01` reboot;
- automatic `mon01` startup;
- service health after reboot;
- real backup restore into temporary CT 900.

## Future direction

When a second physical system exists, deploy an out-of-band availability
watcher outside the `pve01` failure domain.

The main monitoring stack may remain in `mon01`; only the host-down detection
path must be independent.

## Revisit condition

Revisit this decision if:

- monitoring load outgrows the container;
- high availability becomes necessary;
- a second infrastructure node becomes available;
- service isolation requirements increase.
