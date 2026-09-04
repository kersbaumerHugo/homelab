# Runbook - Troubleshooting

## Purpose

Provide a consistent first-response procedure for homelab incidents.

The goal is to gather evidence before changing the system.

## Principle

Prefer:

```text
observe
  |
collect evidence
  |
identify scope
  |
form hypothesis
  |
change one thing
  |
verify
```

Avoid making multiple unrelated changes before understanding the failure.

## 1. Determine scope

Ask:

- Is the network reachable?
- Is pve01 reachable?
- Is mon01 running?
- Are only monitoring services affected?
- Is storage healthy?
- Did a recent deployment occur?

## 2. Check gateway

From the administrative workstation:

```bash
ping -c 2 192.168.10.1
```

If this fails, investigate:

- workstation LAN connectivity;
- switch;
- OPNsense;
- physical cabling.

## 3. Check pve01

```bash
ping -c 2 192.168.10.10
ssh pve01 'hostname && uptime'
```

If ping and SSH fail but the gateway works, investigate:

- whether pve01 is powered on;
- Ethernet link;
- host network configuration;
- switch port;
- physical cable.

## 4. Run platform verification

If pve01 is reachable:

```bash
./scripts/verify-monitoring.sh
```

Use the first failure domain reported by the script as a starting point.

## 5. Check mon01

```bash
ssh pve01 '
pct status 100
pct config 100
'
```

If stopped unexpectedly, inspect Proxmox and guest logs before simply starting
it.

## 6. Check failed systemd units

Host:

```bash
ssh pve01   'systemctl --failed --no-pager'
```

mon01:

```bash
ssh pve01   'pct exec 100 -- systemctl --failed --no-pager'
```

## 7. Check core monitoring services

```bash
ssh pve01 '
pct exec 100 -- systemctl status prometheus --no-pager
pct exec 100 -- systemctl status grafana-server --no-pager
pct exec 100 -- systemctl status ntfy --no-pager
'
```

## 8. Inspect logs

Prometheus:

```bash
ssh pve01   'pct exec 100 -- journalctl -u prometheus -n 100 --no-pager'
```

Grafana:

```bash
ssh pve01   'pct exec 100 -- journalctl -u grafana-server -n 100 --no-pager'
```

ntfy:

```bash
ssh pve01   'pct exec 100 -- journalctl -u ntfy -n 100 --no-pager'
```

Node Exporter:

```bash
ssh pve01   'journalctl -u prometheus-node-exporter -n 100 --no-pager'
```

## 9. Check storage

```bash
ssh pve01 '
df -h
pvesm status
lvs
'
```

SMART:

```bash
ssh pve01 '
smartctl -H /dev/sda
smartctl -H /dev/sdb
'
```

Do not rely only on `/dev/sdX` identity when interpreting which physical disk
is affected. Confirm model information.

## 10. Check custom collectors

Timers:

```bash
ssh pve01 '
systemctl status homelab-lvm-collector.timer --no-pager
systemctl status homelab-smart-collector.timer --no-pager
systemctl status homelab-backup-collector.timer --no-pager
'
```

Metric files:

```bash
ssh pve01 '
ls -l /var/lib/prometheus/node-exporter/homelab_*.prom
'
```

## 11. Check Prometheus target

From mon01:

```bash
ssh pve01 '
pct exec 100 -- promtool query instant   http://127.0.0.1:9090   '''up{job="pve01"}'''
'
```

Expected value:

```text
1
```

## 12. Check recent changes

From the repository:

```bash
git status
git log --oneline -10
```

If the failure appeared immediately after deployment, inspect the corresponding
change before making unrelated runtime changes.

## 13. Preserve evidence

For unexpected crashes or repeated failures, record:

- approximate incident time;
- affected services;
- relevant journal entries;
- temperatures;
- storage state;
- recent deployments;
- current Git commit;
- whether the host rebooted unexpectedly.

## 14. Recovery

Use the smallest recovery action that addresses the identified failure.

Examples:

- restart one failed service;
- redeploy known-good configuration;
- run the monitoring rollback process;
- reconcile drift from Git;
- restore mon01 from backup.

## Escalation criteria

Treat the incident as a host-level problem if:

- pve01 reboots unexpectedly;
- multiple independent services fail simultaneously;
- storage reports media errors;
- temperatures reach unsafe levels;
- network connectivity disappears while OPNsense remains healthy.

Treat the incident as a recovery event if normal service restoration is not
possible without restoring a backup.
