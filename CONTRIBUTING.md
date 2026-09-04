# Contributing

## Purpose

This repository is both the infrastructure source of truth and the operational
record of the homelab.

Changes should preserve reproducibility, reviewability and recoverability.

## Change workflow

Normal infrastructure changes should follow:

```text
branch
  |
local validation
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

## Branches

Use focused branches.

Examples:

```text
feat/backup-monitoring
feat/guest-boot-policy
fix/grafana-alert
docs/platform-baseline
refactor/alert-organization
```

Avoid combining unrelated infrastructure changes in the same branch.

## Before commit

Run the relevant validation.

For monitoring changes:

```bash
./scripts/validate-monitoring.sh
```

For shell scripts:

```bash
shellcheck scripts/*.sh
```

When runtime state changes, perform the relevant deployment and verification
before considering the work complete.

## Pull requests

A pull request should explain:

- what changed;
- why the change is required;
- expected operational impact;
- how it was validated;
- whether rollback or recovery behavior changed.

## Runtime changes

Manual runtime changes are allowed for:

- investigation;
- proof of concept;
- emergency recovery;
- controlled failure injection.

If the change becomes part of intended platform state, it must be represented
in Git afterward.

Unrepresented runtime state is considered drift.

## Documentation requirements

Documentation must be updated when a change affects:

- architecture;
- network topology;
- host inventory;
- storage layout;
- startup ordering;
- backup behavior;
- monitoring behavior;
- recovery procedures;
- security posture;
- reliability risks;
- roadmap status.

Use the documentation update matrix in:

```text
docs/documentation-status.md
```

## ADR requirement

Create or update an Architecture Decision Record when a change:

- introduces a long-lived architectural choice;
- changes a failure-domain boundary;
- changes the source of truth;
- changes recovery strategy;
- introduces a foundational platform dependency;
- intentionally accepts a meaningful risk.

## Runbook requirement

Create or update a runbook when an operator must know how to:

- deploy something;
- stop or start something;
- recover something;
- diagnose a failure;
- restore a backup;
- perform a recurring administrative operation.

## Secrets

Never commit:

- passwords;
- API keys;
- private keys;
- tokens;
- session cookies;
- raw secret-bearing firewall exports;
- secret-bearing state files;
- recovery codes.

The repository is public.

`.gitignore` is a safety control, not a substitute for review.

## Definition of done

Infrastructure work is complete only when applicable items are satisfied:

- desired state is versioned;
- validation passes;
- CI passes;
- deployment succeeds;
- runtime verification succeeds;
- drift is understood;
- recovery impact is documented;
- architecture documentation is current;
- runbooks are current;
- risks are updated;
- ADRs are updated when required.
