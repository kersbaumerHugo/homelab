# Runbook - Disaster Recovery

## Purpose

Describe the current disaster-recovery paths and, equally importantly, the
limits of what can currently be recovered.

## Current recovery maturity

The homelab currently has:

- Git-managed non-secret desired state;
- local mon01 backups;
- tested mon01 restore;
- Proxmox guest startup policy as code;
- backup policy as code;
- monitoring deployment automation.

The homelab does not currently have:

- off-host backup;
- off-site backup;
- second compute host;
- complete bare-metal pve01 rebuild automation.

Therefore some disaster scenarios are only partially recoverable.

## Scenario A - mon01 is corrupted or lost

Status:

**Tested recovery path**

### Recovery source

Local `hdd-backup` vzdump archive.

### Procedure

Use:

```text
docs/runbooks/mon01-backup-restore.md
```

A real restore has already been validated.

## Scenario B - mon01 configuration is broken but CT remains intact

Status:

**Recoverable**

Preferred order:

1. identify whether the failure came from deployment;
2. run runtime verification;
3. use monitoring rollback if applicable;
4. redeploy known-good Git state.

Relevant runbooks:

```text
monitoring-rollback.md
monitoring-deploy.md
```

## Scenario C - backup job configuration is lost

Status:

**Tested recovery path**

The backup job can be reconstructed from Git.

Run:

```bash
./scripts/deploy-backup-jobs.sh
```

Then:

```bash
./scripts/verify-monitoring.sh
```

This reconstruction has been deliberately tested.

## Scenario D - pve01 primary SSD fails but backup HDD survives

Status:

**Partially documented / not yet fully tested**

Expected recovery concept:

```text
replace primary storage
       |
install Proxmox VE
       |
restore baseline host configuration
       |
mount/register hdd-backup
       |
restore mon01
       |
deploy Git-managed policies
       |
verify platform
```

Important limitation:

A complete bare-metal Proxmox rebuild from zero has not yet been executed as a
drill.

Do not label this scenario as validated.

## Scenario E - complete pve01 physical loss

Status:

**Not currently recoverable from the homelab alone**

If the entire physical machine and both internal drives are lost:

- primary workload storage is lost;
- local backup storage is lost;
- monitoring is lost.

Git preserves non-secret desired state, but Git does not contain workload data
or backup archives.

### Current action

Replace hardware and rebuild the infrastructure using documentation and Git.

Application/workload data that existed only on pve01 may not be recoverable.

### Required future mitigation

Off-host backup.

This is the highest-priority unresolved disaster-recovery gap.

## Scenario F - OPNsense appliance failure

Status:

**Partially recoverable**

A configuration backup exists.

Recovery requires replacement or repair of the firewall appliance and restore
of its configuration.

A complete firewall replacement drill has not yet been performed.

## General disaster-response procedure

### 1. Stop unnecessary changes

Do not continue deploying unrelated changes while recovery is underway.

### 2. Identify the failure domain

Determine whether the incident affects:

- one service;
- mon01;
- pve01 storage;
- all of pve01;
- network infrastructure;
- the whole physical site.

### 3. Preserve surviving data

Do not erase or reinitialize surviving disks until the failure has been
understood.

### 4. Identify available recovery sources

Possible current sources:

```text
Git repository
local hdd-backup
OPNsense configuration backup
surviving runtime disks
```

### 5. Choose the smallest recovery scope

Prefer:

```text
service recovery
    before
container recovery
    before
host rebuild
```

when the smaller scope is sufficient.

### 6. Validate after recovery

After recovery, run:

```bash
./scripts/verify-monitoring.sh
```

Also verify any workload-specific state not covered by the monitoring script.

### 7. Record the incident

Document:

- incident time;
- cause if known;
- lost components;
- recovery source;
- recovery duration;
- data loss window;
- unexpected problems;
- required follow-up changes.

## Recovery objectives

Current engineering targets:

```text
RPO <= 24 hours
RTO <= 2 hours
```

These targets currently apply primarily to `mon01`.

They are not yet guaranteed for complete host loss because no independent
backup failure domain exists.

## Disaster-recovery priorities

Current priority order:

1. preserve and validate local backup;
2. acquire second physical backup node;
3. implement off-host backup;
4. test restore from off-host copy;
5. automate more of the pve01 rebuild;
6. add off-site backup;
7. run periodic disaster-recovery exercises.
