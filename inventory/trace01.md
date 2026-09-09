# trace01 Inventory

## Identity

- Hostname: `trace01`
- Proxmox VMID: `101`
- Type: LXC
- Role: tracing backend
- IP: `192.168.10.20`

## Operating system

Debian 13

## Resources

- 2 vCPU
- 4 GiB RAM
- 512 MiB swap
- 16 GiB root disk
- storage: `local-lvm`

## Container configuration

- unprivileged: yes
- nesting: disabled
- automatic startup: enabled
- startup order: 20
- startup delay: 15 seconds
- shutdown timeout: 60 seconds

## Network

- bridge: `vmbr0`
- IPv4: `192.168.10.20/24`
- gateway: `192.168.10.1`

## Services

### Grafana Tempo

Role:

Receives, stores and serves distributed traces for the homelab and Agent Platform.

Planned endpoints:

- OTLP gRPC: `4317`
- Tempo HTTP API: `3200`

## Dependencies

trace01 depends on:

- pve01
- local-lvm
- LAN connectivity
- OPNsense for gateway/DNS

trace01 does not host Prometheus, Grafana or ntfy.

Failure of trace01 must not affect the existing mon01 monitoring stack.

## Storage policy

Tempo will use local storage with bounded retention.

Tracing data is considered operational telemetry and is not a system of record.

## Recovery

trace01 is intended to be reproducible from Git-managed configuration.

A backup policy will be defined after the initial deployment is validated.
