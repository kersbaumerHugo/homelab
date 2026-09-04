# ADR 0002 - Use Git as the Source of Truth

## Status

Accepted

## Date

2026-09-02

## Context

Manual infrastructure configuration creates several operational risks:

- undocumented changes;
- configuration drift;
- dependence on operator memory;
- difficult recovery after system loss;
- poor auditability;
- inconsistent rebuild procedures.

The homelab is intended to function as a DevOps/SRE learning platform, so the
infrastructure should be reproducible and reviewable rather than dependent on
one-time manual configuration.

## Decision

Use Git as the source of truth for all non-secret infrastructure desired state.

Runtime state is treated as derived state whenever practical.

Examples of desired state stored in Git include:

- Prometheus configuration;
- Grafana provisioning;
- Node Exporter configuration;
- custom collectors;
- systemd units;
- Proxmox guest startup policy;
- Proxmox backup policy;
- operational scripts;
- documentation.

The preferred change flow is:

```text
branch
  |
validation
  |
pull request
  |
CI
  |
merge
  |
deployment
  |
runtime verification
```

## Manual changes

Manual runtime changes are permitted for:

- investigation;
- emergency recovery;
- controlled failure injection;
- initial proof of concept.

A manual change that becomes part of the intended platform must be represented
in Git afterward.

Otherwise it is considered drift.

## Secrets

Git is not the source of truth for plaintext secrets.

The public repository must not contain:

- passwords;
- private keys;
- tokens;
- raw firewall exports containing credentials;
- secret-bearing state files.

A separate secret-management mechanism will be introduced when required.

## Consequences

### Positive

- reproducibility;
- auditability;
- peer-reviewable changes;
- drift detection;
- easier recovery;
- usable infrastructure history;
- CI validation.

### Negative

- additional deployment tooling is required;
- some configuration must be normalized before comparison;
- secret management must be handled separately.

## Validation

This model has already been validated through:

- monitoring deployment from Git;
- Grafana provisioning from Git;
- guest boot policy deployment;
- backup job reconstruction after deliberate deletion;
- backup configuration drift detection and reconciliation.

## Revisit condition

Revisit this decision only if a future control plane replaces Git while
retaining equivalent or stronger versioning, review, audit and reconciliation
properties.
