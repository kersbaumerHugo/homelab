# Runbook - mon01 Backup and Restore

## Purpose

Create, inspect and restore backups of `mon01` (CT 100).

## Current backup policy

Job:

```text
mon01-daily
```

Configuration:

```text
VMID: 100
schedule: 03:00
mode: snapshot
compression: zstd
storage: hdd-backup
```

Retention:

```text
daily: 7
weekly: 4
monthly: 3
```

Desired state:

```text
proxmox/pve01/backup-jobs/mon01-daily.yml
```

Deployment:

```text
scripts/deploy-backup-jobs.sh
```

## Verify backup job

```bash
ssh pve01   'pvesh get /cluster/backup/mon01-daily --output-format yaml'
```

Also run:

```bash
./scripts/verify-monitoring.sh
```

## Manual backup

To create an immediate backup:

```bash
ssh pve01   'vzdump 100 --storage hdd-backup --mode snapshot --compress zstd'
```

## Find latest backup

```bash
ssh pve01 '
find /mnt/pve/hdd-backup/dump   -maxdepth 1   -type f   -name "vzdump-lxc-100-*.tar.zst"   -printf "%T@ %p
"   | sort -nr   | head -1
'
```

## Restore drill policy

Never restore a test copy directly over production CT 100.

Use a temporary unused CT ID.

Previously validated temporary ID:

```text
900
```

Always confirm the ID is unused before restore:

```bash
ssh pve01 'pct status 900'
```

A non-existent CT is expected.

## Restore to temporary CT

Identify the backup archive first.

Example:

```bash
ssh pve01 '
pct restore 900   /mnt/pve/hdd-backup/dump/<BACKUP_FILE>.tar.zst   --storage local-lvm
'
```

Replace `<BACKUP_FILE>` with the selected archive.

## Prevent identity collision

Before starting the restored container, change the restored hostname:

```bash
ssh pve01   'pct set 900 --hostname mon01-restore-test'
```

Ensure the restored container does not reuse a conflicting network identity.

If necessary, generate a new MAC address before startup.

Do not start the restored container until production identity conflicts have
been addressed.

## Start the restored container

```bash
ssh pve01 'pct start 900'
```

A systemd nesting warning may appear depending on the container/systemd
combination.

The warning alone is not a reason to enable nesting if the restored services
operate correctly.

## Validate container state

```bash
ssh pve01 'pct status 900'
```

Expected:

```text
status: running
```

## Validate networking

Inside CT 900:

```bash
ssh pve01 '
pct exec 900 -- ip -br addr
pct exec 900 -- ip route
'
```

Validate gateway:

```bash
ssh pve01   'pct exec 900 -- ping -c 2 192.168.10.1'
```

Validate Internet reachability:

```bash
ssh pve01   'pct exec 900 -- ping -c 2 1.1.1.1'
```

Validate DNS:

```bash
ssh pve01   'pct exec 900 -- getent hosts github.com'
```

## Validate monitoring services

```bash
ssh pve01 '
pct exec 900 -- systemctl is-active prometheus
pct exec 900 -- systemctl is-active grafana-server
pct exec 900 -- systemctl is-active ntfy
'
```

Expected:

```text
active
active
active
```

Prometheus health:

```bash
ssh pve01   'pct exec 900 -- curl --fail --silent http://127.0.0.1:9090/-/healthy'
```

Grafana health:

```bash
ssh pve01   'pct exec 900 -- curl --fail --silent http://127.0.0.1:3000/api/health'
```

ntfy health:

```bash
ssh pve01   'pct exec 900 -- curl --fail --silent http://127.0.0.1/v1/health'
```

## Validate important configuration

```bash
ssh pve01 '
pct exec 900 -- test -f /etc/prometheus/prometheus.yml
pct exec 900 -- test -d /etc/grafana/provisioning
pct exec 900 -- test -f /etc/ntfy/server.yml
'
```

## Successful restore criteria

A restore drill is successful when:

- CT boots;
- networking works;
- gateway works;
- Internet works;
- DNS works;
- Prometheus is healthy;
- Grafana is healthy;
- ntfy is healthy;
- important configuration files exist.

## Cleanup test CT

After successful validation:

```bash
ssh pve01 '
pct stop 900
pct destroy 900 --purge 1
'
```

Confirm the temporary CT no longer exists.

## Production recovery

If CT 100 is genuinely lost, do not immediately restore over the failed
instance.

First:

1. preserve any available evidence;
2. identify the failure cause;
3. select the latest valid backup;
4. verify backup artifact availability;
5. determine whether CT 100 should be removed or retained for investigation.

Then perform a controlled restore.

## Previously validated restore

A complete real restore to CT 900 has already been performed successfully,
including network and service validation.

This proves the current local `mon01` backup is restorable.
