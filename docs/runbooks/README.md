# Runbooks

Runbooks are executable operational procedures.

They are intended to be used during normal operations, maintenance,
troubleshooting and recovery.

## Current runbooks

### [Platform Boot and Shutdown](boot-and-shutdown.md)

Use for:

- normal platform startup;
- validating automatic mon01 startup;
- graceful platform shutdown.

### [Monitoring Deployment](monitoring-deploy.md)

Use for:

- deploying Git-managed monitoring configuration;
- validating a monitoring deployment;
- confirming runtime synchronization.

### [Monitoring Rollback](monitoring-rollback.md)

Use for:

- failed monitoring deployments;
- rollback investigation;
- returning to known-good monitoring state.

### [mon01 Backup and Restore](mon01-backup-restore.md)

Use for:

- manual mon01 backup;
- finding backup artifacts;
- restore drills;
- validating restored services.

### [Troubleshooting](troubleshooting.md)

Use as the default first-response procedure for:

- network problems;
- pve01 problems;
- mon01 problems;
- monitoring failures;
- storage issues;
- custom collector issues.

### [Disaster Recovery](disaster-recovery.md)

Use for:

- mon01 loss;
- backup policy loss;
- primary SSD failure;
- complete host-loss analysis;
- disaster-recovery decision making.

## Runbook design rules

A runbook should:

- define its purpose;
- define prerequisites;
- use copyable commands;
- state expected results;
- identify destructive commands clearly;
- include success criteria;
- distinguish tested procedures from theoretical ones.

## Safety rule

Do not turn a theoretical recovery path into a claimed validated procedure
until it has actually been tested.

## Update rule

Update a runbook in the same change that modifies the operational procedure it
describes.
