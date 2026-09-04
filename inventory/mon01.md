# mon01 Inventory

## Identity

- Hostname: `mon01`
- Proxmox VMID: `100`
- Type: LXC
- Role: monitoring and observability
- IP: `192.168.10.162`

## Operating system

Debian 13

## Resources

- 2 vCPU
- 4 GiB RAM
- 512 MiB swap
- 32 GB disk
- storage: local-lvm

## Container configuration

- unprivileged: yes
- nesting: disabled
- automatic startup: enabled
- startup order: 10
- startup delay: 30 seconds
- shutdown timeout: 60 seconds

## Services

### Prometheus

Role:

Metrics storage and query engine.

### Grafana

Role:

Dashboards and alert evaluation.

### ntfy

Role:

Self-hosted alert notification transport.

Topic:

`homelab-alerts`

## Dependencies

mon01 depends on:

- pve01
- local-lvm
- LAN connectivity
- OPNsense for gateway/DNS

## Recovery

mon01 is protected by the `mon01-daily` Proxmox backup job.

A complete restore has been tested successfully.
