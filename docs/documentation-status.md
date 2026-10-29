# Documentation Status

## Purpose

This document tracks the documentation completeness of the homelab and defines
the maintenance contract between infrastructure changes and documentation.

Baseline date:

**2026-09-04**

## Current documentation coverage

| Area | Documented | Tested where applicable | Status |
|---|---:|---:|---|
| High-level architecture | Yes | N/A | Complete |
| Network architecture | Yes | Partially | Complete for current state |
| Compute architecture | Yes | Yes | Complete for current state |
| Storage architecture | Yes | Yes | Complete for current state |
| Observability architecture | Yes | Yes | Complete for current state |
| Inference architecture | Yes | Yes | Complete for current state |
| Backup architecture | Yes | Yes | Complete for current state |
| Current platform state | Yes | Yes | Complete |
| Reliability posture | Yes | Yes | Complete |
| Security posture | Yes | Partially | Complete for current state |
| Known risk register | Yes | N/A | Complete |
| Roadmap | Yes | N/A | Complete |
| System inventory | Yes | N/A | Complete |
| ADRs for foundational decisions | Yes | N/A | Complete for current decisions |
| Boot/shutdown runbook | Yes | Yes | Complete |
| Monitoring deploy runbook | Yes | Yes | Complete |
| Monitoring rollback runbook | Yes | Yes | Complete |
| mon01 backup/restore runbook | Yes | Yes | Complete |
| Inference server runbook | Yes | Partially | Complete for current scope |
| Troubleshooting runbook | Yes | Partially | Complete for current scope |
| Disaster recovery runbook | Yes | Partially | Complete for current capability |
| Guest management runbook | Yes | Yes | Complete |
| Bare-metal pve01 rebuild | Partial | No | Gap |
| OPNsense replacement drill | Partial | No | Gap |
| Off-host backup restore | No | No | Blocked by hardware |
| Off-site recovery | No | No | Future |

## Documentation completeness rule

A platform capability is considered fully documented when:

1. its current architecture is described;
2. its runtime desired state is discoverable;
3. its operational procedure is documented when necessary;
4. its failure impact is understood;
5. its recovery procedure is documented;
6. tested behavior is distinguished from theoretical behavior;
7. relevant risks and ADRs are current.

## Change-to-documentation matrix

| Change type | Required documentation review |
|---|---|
| New physical host | Inventory, architecture, reliability, risks, roadmap |
| New network segment | Network, security, inventory, ADR if architectural |
| New storage device | Storage, inventory, reliability, risks |
| New foundational service | Architecture, operations, runbook, ADR |
| Monitoring change | Observability, deploy/rollback runbooks, current state |
| New alert class | Observability, current state |
| Backup change | Backup architecture, restore runbook, reliability, risks |
| Startup dependency | Compute architecture, boot runbook, ADR when significant |
| Security boundary change | Security posture, network, ADR, risks |
| Recovery behavior change | DR runbook, reliability, current state |
| Risk mitigation completed | Known risks, roadmap, current state |
| Hardware replacement | Inventory, architecture, risk register |

## Validation status vocabulary

Use these terms consistently:

### Implemented

The capability exists.

### Validated

The capability has been tested successfully.

### Partially validated

Some important behavior has been tested, but the complete recovery or failure
scenario has not.

### Planned

The capability is intentionally scheduled for future work.

### Blocked

The capability cannot currently proceed because of an explicit dependency.

### Accepted risk

The limitation is known and deliberately tolerated for the current stage.

## Known documentation gaps

### Bare-metal pve01 rebuild

The conceptual recovery path is documented, but a full rebuild from empty
hardware has not yet been performed.

Do not claim bare-metal recovery as validated.

### OPNsense replacement

A configuration backup exists, but a full replacement-and-restore drill has
not yet been executed.

### Off-host and off-site recovery

These cannot be documented as implemented until independent storage hardware
exists.

## Documentation review trigger

Perform a documentation review when any of the following occurs:

- major infrastructure milestone completed;
- new physical equipment introduced;
- significant recovery procedure tested;
- new platform service introduced;
- risk severity changes;
- architectural decision is replaced;
- before publishing the repository as a portfolio reference after major
  changes.

## Documentation definition of done

The documentation baseline is considered complete for the current platform
when the repository can answer, without external conversation history:

```text
What exists?
How is it connected?
How does it start?
How does it shut down?
How is monitoring deployed?
How is runtime state verified?
How do backups work?
How do restores work?
What failures have been tested?
What is not tested?
What are the current risks?
Why were major decisions made?
What should be built next?
```

As of the baseline date, the repository documentation is intended to satisfy
these questions for the current platform state.

## Current documentation completion status

### Completed

- System inventory: `pve01.md` documents all hardware, storage, and guests
- Compute architecture: `docs/architecture/compute.md` includes all guests
- Guest YAML files: All guests have `.yml` files in `proxmox/pve01/guests/`
- Network addressing: `network/addressing.yml` updated for DHCP reservations
- Script discovery: `scripts/deploy-guest-policy.sh` discovers guest type dynamically
- Documentation status tracking: `docs/documentation-status.md` updated
- Runbook index: `docs/runbooks/README.md` includes all runbooks

### In progress

- Bare-metal pve01 rebuild: Conceptual recovery documented, not yet tested

### Future

- Off-host backup restore: Blocked by hardware availability
- Off-site recovery: Planned for future hardware acquisition
