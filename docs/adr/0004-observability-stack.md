# ADR 0004 - Use Prometheus, Grafana and ntfy for Observability

## Status

Accepted

## Date

2026-08-31

## Context

The platform required a small, self-hosted observability stack capable of:

- collecting host metrics;
- querying infrastructure state;
- displaying dashboards;
- evaluating alerts;
- delivering notifications.

The selected tools needed to be widely used, automatable and suitable for
Git-managed configuration.

## Decision

Use:

- Prometheus for metrics collection and PromQL;
- Grafana for dashboards and alerting;
- ntfy for self-hosted notifications;
- Prometheus Node Exporter for host metrics.

Custom infrastructure metrics are exposed through the Node Exporter textfile
collector.

Current custom collectors:

- LVM;
- SMART;
- backup state.

## Collector pattern

Custom collectors should:

- execute independently;
- use systemd timers;
- write metrics atomically;
- expose collector success;
- expose collector freshness.

This keeps Node Exporter focused on serving metrics while acquisition logic
remains isolated.

## Alert provisioning convention

Grafana alert rules are stored in Git.

Preferred convention:

```text
one alert rule = one provisioning file
```

Current logical folders:

```text
Homelab - Availability
Homelab - Memory
Homelab - Temperature
Homelab - Storage
Homelab - Monitoring
Homelab - Tests
```

## Consequences

### Positive

- standard Prometheus ecosystem;
- powerful query language;
- infrastructure-as-code-friendly provisioning;
- self-hosted alert delivery;
- extensible custom metrics;
- strong portability.

### Negative

- metrics are hosted inside the same physical failure domain as `pve01`;
- logging and distributed tracing are not yet part of the platform;
- additional operational tooling is required for safe provisioning.

## Validation

Validated capabilities include:

- pve01 scrape target;
- CPU, memory and filesystem metrics;
- hardware temperature metrics;
- LVM metrics;
- SMART metrics;
- backup metrics;
- Grafana provisioning;
- ntfy notification delivery;
- controlled alert failure injection.

## Future direction

Possible future additions:

- Loki for logs;
- black-box probing;
- external host-down monitoring;
- distributed tracing;
- SLO dashboards.

These should complement the existing metrics platform rather than replace it
without a clear operational reason.
