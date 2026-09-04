# Runbook - Deploy Monitoring Configuration

## Purpose

Deploy the Git-managed monitoring desired state safely to `pve01` and `mon01`.

## Primary command

```bash
./scripts/deploy-monitoring.sh
```

## Preconditions

Before deployment:

- workstation is connected to the homelab LAN;
- `pve01` is reachable by SSH key;
- `mon01` is running;
- repository working tree contains the intended changes;
- changes have been reviewed locally;
- no known active incident is being investigated unless the deployment is
  part of the recovery.

## Recommended Git workflow

```bash
git status
git branch --show-current
```

Normal change flow:

```text
feature branch
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
```

For development testing before merge, deploy only intentional branch state.

## 1. Validate repository

Run:

```bash
./scripts/validate-monitoring.sh
```

Validation includes:

- YAML;
- Grafana alert enums;
- Node Exporter configuration;
- Python collectors;
- systemd units;
- dashboards;
- ShellCheck;
- Prometheus configuration;
- Grafana UID sanity.

Do not proceed if validation fails.

## 2. Deploy

```bash
./scripts/deploy-monitoring.sh
```

The deployment process performs:

```text
pre-deployment validation
        |
SSH / CT checks
        |
candidate upload
        |
configuration validation
        |
runtime backup
        |
deployment
        |
service restart
        |
health checks
```

## 3. Verify runtime

After a successful deployment:

```bash
./scripts/verify-monitoring.sh
```

Expected:

```text
Homelab verification successful
```

## 4. Inspect Grafana

When the change affects dashboards or alerting, validate through Grafana that:

- provisioning loaded successfully;
- expected folder exists;
- expected alert rule exists;
- no unexpected duplicate rule exists.

## 5. Inspect notification behavior

When notification or alert logic changes, perform a safe controlled test if
practical.

Do not create destructive failure conditions only to validate alerting.

## Failure behavior

The deployment script is transactional.

If a failure occurs after runtime modifications begin, the script attempts to
restore the previous runtime state automatically.

See:

```text
docs/runbooks/monitoring-rollback.md
```

## Deployment completion criteria

Deployment is complete only when:

- deploy script succeeds;
- services are healthy;
- `verify-monitoring.sh` succeeds;
- Git-to-runtime drift checks are green.

A successful copy of files without runtime verification is not considered a
complete deployment.
