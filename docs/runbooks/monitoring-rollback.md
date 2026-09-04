# Runbook - Monitoring Rollback

## Purpose

Recover the monitoring stack after a failed or invalid deployment.

## Normal rollback path

The preferred rollback mechanism is automatic.

`scripts/deploy-monitoring.sh` creates backups of the deployed state before
applying new configuration.

If deployment fails after changes begin, its EXIT trap attempts to restore the
previous configuration.

## 1. Observe deployment result

If deployment prints a rollback message, do not immediately make additional
manual changes.

First inspect the current state:

```bash
./scripts/verify-monitoring.sh
```

## 2. Check services

```bash
ssh pve01 '
pct exec 100 -- systemctl is-active prometheus
pct exec 100 -- systemctl is-active grafana-server
pct exec 100 -- systemctl is-active ntfy
systemctl is-active prometheus-node-exporter
'
```

## 3. Inspect failed units

```bash
ssh pve01 '
systemctl --failed --no-pager
pct exec 100 -- systemctl --failed --no-pager
'
```

## 4. Inspect service logs

Prometheus:

```bash
ssh pve01   'pct exec 100 -- journalctl -u prometheus -n 100 --no-pager'
```

Grafana:

```bash
ssh pve01   'pct exec 100 -- journalctl -u grafana-server -n 100 --no-pager'
```

Node Exporter:

```bash
ssh pve01   'journalctl -u prometheus-node-exporter -n 100 --no-pager'
```

Custom collector example:

```bash
ssh pve01   'journalctl -u homelab-backup-collector.service -n 100 --no-pager'
```

## 5. Preferred manual recovery

If automatic rollback succeeded but the candidate branch remains invalid:

1. fix the repository;
2. run validation;
3. redeploy.

```bash
./scripts/validate-monitoring.sh
./scripts/deploy-monitoring.sh
./scripts/verify-monitoring.sh
```

## 6. Recover from known-good Git state

If the current working branch is unusable, return to a known-good Git commit or
`main` after preserving any investigation data.

Example workflow:

```bash
git status
git log --oneline -10
```

Do not discard uncommitted work without intentionally saving or reviewing it.

After selecting a known-good state:

```bash
./scripts/validate-monitoring.sh
./scripts/deploy-monitoring.sh
./scripts/verify-monitoring.sh
```

## Manual backup directories

The deployment tooling stores timestamped configuration backups on runtime
systems.

Typical locations include:

```text
/root/homelab-config-backups/
/root/homelab-host-config-backups/
```

These directories exist for recovery support.

Direct restoration from these paths should be treated as a last-resort manual
operation because exact contents depend on the deployment version.

Prefer the scripted rollback or redeployment of known-good Git state.

## Rollback validation

A rollback is considered successful only when:

- Prometheus is healthy;
- Grafana is healthy;
- ntfy is healthy;
- Node Exporter is healthy;
- required custom metrics are present;
- Git-to-runtime state is understood;
- runtime verification passes or any remaining failure is explicitly
  explained.

## Previously validated behavior

A deliberate invalid monitoring deployment has already triggered the rollback
path successfully.

This runbook documents the operational response if that mechanism is needed
again.
