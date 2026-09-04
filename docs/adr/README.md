# Architecture Decision Records

Architecture Decision Records capture important long-lived technical
decisions.

They explain why the platform is designed the way it is.

## ADR index

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-disable-openipmi.md) | Disable OpenIPMI on pve01 | Accepted |
| [0002](0002-git-as-source-of-truth.md) | Use Git as the source of truth | Accepted |
| [0003](0003-monitoring-in-mon01.md) | Run the monitoring stack in mon01 | Accepted with known limitation |
| [0004](0004-observability-stack.md) | Use Prometheus, Grafana and ntfy for observability | Accepted |
| [0005](0005-local-backup-strategy.md) | Use local Proxmox vzdump backups for mon01 | Accepted as interim layer |
| [0006](0006-guest-startup-ordering.md) | Manage guest startup ordering explicitly | Accepted |
| [0007](0007-off-host-backup-deferred.md) | Defer off-host backup until independent hardware exists | Accepted risk / deferred |

## When to create an ADR

Create an ADR when a change:

- introduces a foundational platform dependency;
- changes a major trust or failure boundary;
- establishes a source-of-truth model;
- changes backup or recovery strategy;
- changes orchestration strategy;
- intentionally accepts a significant architectural risk;
- is likely to be questioned later with "why did we do this?"

## ADR lifecycle

Recommended statuses:

```text
Proposed
Accepted
Deprecated
Superseded
Rejected
```

Do not rewrite historical decisions only because the platform later changes.

When a decision is replaced, create a new ADR and mark the old one as
superseded.

## ADR template

```markdown
# ADR NNNN - Decision title

## Status

Proposed

## Date

YYYY-MM-DD

## Context

What problem or constraint requires a decision?

## Decision

What was decided?

## Consequences

### Positive

- ...

### Negative

- ...

## Validation

How was the decision validated?

## Revisit condition

Under what conditions should the decision be reconsidered?
```
