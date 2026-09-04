# Runbook - Platform Boot and Shutdown

## Purpose

Safely start and stop the current homelab platform.

## Scope

Current sequence:

```text
OPNsense / network
      |
      v
pve01
      |
      v
mon01
      |
      +-- Prometheus
      +-- Grafana
      +-- ntfy
```

## Normal boot

### 1. Confirm network infrastructure

Confirm that:

- ISP modem is powered;
- OPNsense is powered;
- Ethernet switch is powered.

Expected gateway:

```text
192.168.10.1
```

Optional workstation check:

```bash
ping -c 2 192.168.10.1
```

### 2. Power on pve01

Power on the physical `pve01` host.

`mon01` should start automatically through Proxmox guest orchestration.

Do not manually start CT 100 unless automatic startup has failed.

### 3. Wait for pve01

From the administrative workstation:

```bash
ping -c 2 192.168.10.10
ssh pve01 'hostname && uptime'
```

Expected hostname:

```text
pve01
```

### 4. Validate mon01

```bash
ssh pve01 'pct status 100'
```

Expected:

```text
status: running
```

### 5. Validate monitoring services

```bash
ssh pve01 '
pct exec 100 -- systemctl is-active prometheus
pct exec 100 -- systemctl is-active grafana-server
pct exec 100 -- systemctl is-active ntfy
'
```

Expected:

```text
active
active
active
```

### 6. Run full verification

From the repository:

```bash
./scripts/verify-monitoring.sh
```

Expected final state:

```text
Homelab verification successful
```

## Normal shutdown

Preferred method:

```bash
./scripts/shutdown-homelab.sh
```

The script:

- checks pve01 connectivity;
- displays current guests;
- verifies Proxmox guest orchestration;
- asks for confirmation;
- requests `systemctl poweroff`;
- waits for the host to become unreachable.

Do not remove power before pve01 has shut down.

## Manual graceful shutdown

If the helper script is unavailable:

```bash
ssh pve01 'systemctl poweroff'
```

Proxmox should stop guests through its normal shutdown orchestration.

## Do not use unless required

Avoid force operations during normal shutdown:

```bash
pct stop 100
poweroff -f
```

These bypass or reduce graceful shutdown behavior.

## Boot failure troubleshooting

If pve01 is reachable but mon01 is not running:

```bash
ssh pve01 '
pct status 100
pct config 100 | grep -E "^(onboot|startup):"
systemctl status pve-guests.service --no-pager
'
```

Expected policy:

```text
onboot: 1
startup: order=10,up=30,down=60
```

If the desired state has drifted, redeploy the guest policy from Git.

## Success criteria

Platform boot is complete when:

- pve01 is reachable;
- mon01 is running;
- Prometheus is active;
- Grafana is active;
- ntfy is active;
- runtime verification passes.
