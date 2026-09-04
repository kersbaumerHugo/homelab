# Platform Roadmap

## Purpose

This roadmap defines the next major engineering milestones for the homelab.

It is ordered primarily by reliability and platform foundations rather than by
feature novelty.

The roadmap should evolve as the infrastructure changes.

## Current baseline

As of 2026-09-04, the platform has:

- dedicated OPNsense firewall;
- Proxmox host `pve01`;
- monitoring container `mon01`;
- Prometheus;
- Grafana;
- ntfy;
- Node Exporter;
- LVM monitoring;
- SMART monitoring;
- backup monitoring;
- Grafana alerting;
- CI validation;
- transactional monitoring deployment;
- rollback;
- runtime verification;
- guest boot policy as code;
- backup policy as code;
- tested backup restore;
- backup drift detection;
- backup failure injection;
- graceful shutdown tooling.

## Milestone 1 - Local operational baseline

Status:

**Completed**

Objectives:

- install and stabilize Proxmox;
- establish dedicated firewall;
- deploy monitoring;
- collect host telemetry;
- add alerting;
- version non-secret configuration;
- create local backup;
- validate restore.

Exit criteria:

- monitoring survives normal restart;
- mon01 starts automatically;
- local backup job runs;
- restore has been tested;
- critical configuration is versioned.

Result:

Completed.

---

## Milestone 2 - Documentation baseline

Status:

**In progress**

Objectives:

- architecture documentation;
- inventory;
- operations documentation;
- ADRs;
- runbooks;
- risk register;
- roadmap;
- current-state documentation.

Exit criteria:

A new operator should be able to answer from the repository:

- what exists;
- how components are connected;
- how services start and stop;
- how monitoring is deployed;
- how backup works;
- how restore works;
- which failures have been tested;
- which risks remain open;
- what the next milestone is.

---

## Milestone 3 - Off-host backup

Status:

**Blocked by hardware**

Objective:

Create a physically independent backup failure domain.

Preferred initial architecture:

```text
pve01
  |
  +-- local backup
  |
  +------ network ------> backup01
                         Proxmox Backup Server
```

Requirements:

- second physical system;
- independent storage;
- backup monitoring;
- restore validation;
- documented retention;
- documented recovery procedure.

Target:

- local RPO <= 24h;
- remote-copy freshness objective <= 30h.

Potential implementation:

Proxmox Backup Server.

---

## Milestone 4 - External availability monitoring

Status:

**Planned**

Objective:

Detect complete pve01 failure from outside pve01.

Target architecture:

```text
watcher01
   |
   +-- pve01 reachability
   +-- OPNsense reachability
   +-- critical endpoint checks
   +-- external notification path
```

This workload should run on a different physical system from pve01.

---

## Milestone 5 - Power resilience

Status:

**Planned**

Objectives:

- introduce UPS;
- monitor UPS state;
- define low-battery shutdown behavior;
- validate automatic graceful shutdown;
- document power recovery.

Exit criteria:

A power-loss test can demonstrate controlled guest and host shutdown.

---

## Milestone 6 - Thermal remediation

Status:

**Planned / hardware change required**

Objectives:

- replace inadequate CPU cooler;
- repeat stress test;
- validate temperatures under sustained load;
- define safe workload envelope.

Exit criteria:

Sustained CPU load no longer causes unacceptable thermal throttling.

---

## Milestone 7 - Configuration management

Status:

**Planned**

Objective:

Reduce host and guest configuration that still depends on imperative scripts
or manual state.

Potential tooling:

- Ansible;
- OpenTofu;
- Proxmox API;
- reusable roles/modules.

Likely first targets:

- package installation;
- systemd units;
- host telemetry;
- LXC provisioning;
- network-independent guest configuration.

---

## Milestone 8 - Network segmentation

Status:

**Planned**

Trigger:

Additional workload classes such as IoT, Home Assistant, AI services or
externally reachable applications.

Potential segments:

```text
Management
Infrastructure
Applications
IoT
User devices
```

Objectives:

- reduce flat-LAN trust;
- define inter-zone firewall policy;
- document trust boundaries.

---

## Milestone 9 - Central logging

Status:

**Planned**

Potential implementation:

Loki.

Objectives:

- centralize host logs;
- centralize service logs;
- correlate alerts with logs;
- improve post-incident investigation.

This milestone should complement, not replace, metrics.

---

## Milestone 10 - Kubernetes / K3s

Status:

**Deferred**

Kubernetes should be introduced only when the platform has enough workloads to
justify the operational complexity.

Prerequisites should include:

- reliable compute;
- backup strategy;
- stable network;
- monitoring;
- documented operations;
- adequate cooling;
- preferably more than one compute node.

Potential goals:

- K3s;
- GitOps;
- Argo CD;
- declarative application deployment.

---

## Milestone 11 - Local AI runtime platform

Status:

**Future**

The homelab is expected to eventually host local AI and agent workloads.

Infrastructure prerequisites include:

- adequate thermal solution;
- suitable GPU/accelerator;
- reliable storage;
- workload isolation;
- observability;
- backup strategy.

This work should not compromise the reliability of foundational
infrastructure services.

---

## Milestone 12 - Off-site backup

Status:

**Future**

Objective:

Maintain a recoverable copy outside the primary physical site.

Target model:

```text
production
    |
local backup
    |
off-host backup
    |
off-site encrypted copy
```

This milestone moves the backup strategy toward a practical 3-2-1 model.

---

## Priority order

Current recommended priority:

```text
1. Documentation baseline
2. Adequate CPU cooling
3. Second physical node / off-host backup
4. External availability monitoring
5. UPS / power resilience
6. Configuration management
7. Network segmentation
8. Central logging
9. Additional workloads
10. Kubernetes / GitOps
11. AI platform expansion
12. Off-site backup maturation
```

## Roadmap rule

New platform features should not be prioritized over unresolved foundational
reliability risks unless there is a clear reason to do so.

The roadmap is intentionally infrastructure-first.
