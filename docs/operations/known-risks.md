# Known Risks

## Purpose

This document is the current risk register for the homelab.

Risks are documented explicitly so that missing capabilities are treated as
known engineering constraints rather than being forgotten.

Severity is qualitative and reflects the current platform stage.

## Risk summary

| ID | Risk | Severity | Current mitigation | Status |
|---|---|---|---|---|
| R-001 | Complete loss of pve01 | Critical | Local backup only | Open |
| R-002 | Backup stored in same physical host | Critical | Separate HDD | Open |
| R-003 | Monitoring hosted on monitored node | High | Local monitoring only | Open |
| R-004 | No UPS / power protection | High | Graceful manual shutdown | Open |
| R-005 | Inadequate CPU cooling | High | Thermal monitoring / avoid sustained load | Open |
| R-006 | OPNsense single point of failure | High | Config backup | Open |
| R-007 | Ethernet switch single point of failure | Medium | None | Accepted |
| R-008 | Flat LAN / limited segmentation | Medium | OPNsense boundary | Open |
| R-009 | No formal secret-management platform | Medium | Secrets excluded from Git | Open |
| R-010 | Temporary GPU / nomodeset dependency | Low | Stable current boot configuration | Open |
| R-011 | No automated periodic restore drill | Medium | Manual restore tested | Open |
| R-012 | No off-site backup | Critical | Local backup only | Open |

## R-001 - Complete loss of pve01

Severity:

**Critical**

### Description

pve01 is currently the only compute host.

Loss of the machine removes:

- running workloads;
- mon01;
- Prometheus;
- Grafana;
- ntfy;
- access to both local storage devices.

### Current mitigation

- local mon01 backup;
- configuration stored in Git;
- restore procedure tested;
- boot policy stored in Git.

### Remaining exposure

The backup HDD is still physically inside pve01.

### Exit criterion

Introduce a second physical system capable of receiving recoverable copies of
critical workloads.

---

## R-002 - Backup is not off-host

Severity:

**Critical**

### Description

The primary SSD and backup HDD are separate devices but remain inside the same
physical machine.

### Current mitigation

A separate physical HDD protects against some SSD-level failures.

### Remaining exposure

The following events can still remove production and backup simultaneously:

- theft;
- fire;
- catastrophic host damage;
- severe electrical event;
- complete physical loss of the system.

### Exit criterion

Replicate critical backups to an independent physical system.

---

## R-003 - Monitoring failure domain

Severity:

**High**

### Description

Prometheus, Grafana and ntfy run inside mon01, which runs on pve01.

A complete pve01 failure therefore removes both the monitored system and the
monitoring system.

### Current mitigation

Infrastructure health is monitored while pve01 is running.

### Exit criterion

Deploy a lightweight external watcher on a physically independent node.

---

## R-004 - No power protection

Severity:

**High**

### Description

No UPS is currently part of the documented platform.

Unexpected power loss can interrupt:

- Proxmox;
- running containers;
- backup operations;
- disk writes.

### Current mitigation

A graceful shutdown script exists for planned shutdowns.

### Exit criterion

Add UPS-backed power and document automatic shutdown behavior.

---

## R-005 - CPU thermal limitation

Severity:

**High**

### Description

The current Intel stock-style cooler is inadequate for the i7-9700K under
sustained load.

Stress testing reached approximately 92-94 C and caused thermal throttling.

### Current mitigation

- CPU temperature monitoring;
- alerting;
- sustained heavy workloads avoided.

### Exit criterion

Install an adequate CPU cooling solution and repeat thermal stress testing.

---

## R-006 - OPNsense is a single point of failure

Severity:

**High**

### Description

The dedicated OPNsense appliance is the only current network gateway.

Its loss interrupts normal LAN routing and upstream connectivity.

### Current mitigation

A configuration backup exists.

### Exit criterion

Define a tested firewall recovery procedure and, if availability requirements
justify it, introduce redundant gateway capability.

---

## R-007 - Ethernet switch is a single point of failure

Severity:

**Medium**

### Description

The current LAN depends on one Ethernet switch.

### Current mitigation

None beyond hardware replacement.

### Decision

Accepted for the current scale.

---

## R-008 - Flat LAN

Severity:

**Medium**

### Description

Infrastructure and client systems currently share a broadly trusted LAN.

### Current mitigation

OPNsense provides the perimeter security boundary.

### Exit criterion

Introduce segmentation when additional workload classes justify it.

Potential segments:

- management;
- infrastructure;
- IoT;
- user devices;
- application workloads.

---

## R-009 - No centralized secret management

Severity:

**Medium**

### Description

Secrets are intentionally excluded from Git, but no formal secrets-management
platform exists.

### Current mitigation

Repository policy and `.gitignore`.

### Exit criterion

Introduce a versioned encrypted-secret workflow or dedicated secrets manager.

---

## R-010 - Temporary display configuration

Severity:

**Low**

### Description

pve01 currently uses a temporary NVIDIA GT610 and persistent `nomodeset`.

### Current mitigation

The current configuration boots reliably.

### Exit criterion

Replace or remove the temporary GPU requirement and revalidate boot behavior.

---

## R-011 - Restore validation is manual

Severity:

**Medium**

### Description

A real mon01 restore has been validated, but restore drills are not yet
executed automatically or on a defined recurring cadence.

### Current mitigation

A successful manual restore drill is documented.

### Exit criterion

Define a recurring restore-test schedule and automate as much validation as is
safe.

---

## R-012 - No off-site backup

Severity:

**Critical**

### Description

There is currently no backup copy outside the physical site.

### Current mitigation

Local backup only.

### Exit criterion

Maintain at least one recoverable encrypted copy outside the primary physical
location.

## Risk-management rule

A risk should only be marked closed when:

1. the mitigation is implemented;
2. the implementation is documented;
3. the relevant recovery or failure behavior is tested where practical.
