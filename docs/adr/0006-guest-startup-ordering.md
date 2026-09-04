# ADR 0006 - Manage Guest Startup Ordering Explicitly

## Status

Accepted

## Date

2026-09-03

## Context

Infrastructure workloads should return automatically after a normal host boot.

Relying on manual guest startup creates unnecessary recovery work and makes the
platform dependent on operator presence.

Future services may also have startup dependencies.

## Decision

Use Proxmox guest startup policies and manage the desired state in Git.

Current `mon01` policy:

```text
onboot = true
order = 10
startup delay = 30 seconds
shutdown timeout = 60 seconds
```

The policy is stored under:

```text
proxmox/pve01/guests/mon01.yml
```

## Ordering convention

Reserve ranges in increments of ten:

```text
10 - monitoring / foundational infrastructure
20 - core infrastructure
30 - stateful services
40 - application services
50 - optional workloads
```

The spacing allows future workloads to be inserted without redesigning the
entire order.

## Important limitation

Proxmox startup ordering provides sequencing and delay.

It does not prove application health.

For example:

```text
mon01 started
```

does not necessarily mean:

```text
Prometheus healthy
Grafana healthy
ntfy healthy
```

Application health remains the responsibility of runtime verification and
service-level monitoring.

## Validation

A real `pve01` reboot was performed.

Validated outcome:

- pve01 booted;
- CT 100 started automatically;
- Prometheus became active;
- Grafana became active;
- ntfy became active.

## Consequences

### Positive

- automatic infrastructure recovery after normal reboot;
- predictable startup order;
- declarative desired state;
- easier future dependency management.

### Negative

- startup delays are time-based rather than health-based;
- complex dependency graphs may eventually require a stronger orchestration
  mechanism.

## Future direction

If workloads develop strict service dependencies, introduce explicit health
gates or a higher-level orchestration mechanism rather than relying only on
fixed delays.
