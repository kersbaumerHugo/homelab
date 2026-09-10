# agent01 Inventory

## Identity

- Hostname: `agent01`
- Proxmox VMID: `102`
- Type: LXC
- Role: Agent Platform application workload
- IP: `192.168.10.30`

## Operating system

Debian 13

## Resources

- 2 vCPU
- 2 GiB RAM
- 512 MiB swap
- 16 GiB root disk
- storage: `local-lvm`

## Sizing evidence

The pre-deployment Agent Platform baseline measured approximately:

- API RSS: 86.6 MiB
- MCP RSS: 97.1 MiB
- combined RSS: 183.7 MiB
- repository footprint: 509 MiB
- Python virtual environment: 476 MiB

The allocation intentionally leaves substantial experiment headroom without
copying the larger resource profiles of monitoring workloads.

## Container configuration

- unprivileged: yes
- nesting: disabled
- automatic startup: enabled
- startup order: 30
- startup delay: 15 seconds
- shutdown timeout: 60 seconds

## Network

- bridge: `vmbr0`
- IPv4: `192.168.10.30/24`
- gateway: `192.168.10.1`

The address is outside the configured dynamic DHCP range and no conflicting
host was observed during preflight checks.

## Planned services

### Agent Platform API

Role:

Hosts the internal Model Gateway and platform API.

Planned port:

- API / metrics: `8000`

### Agent Platform MCP Server

Role:

Exposes Agent Platform capabilities through MCP.

Planned port:

- MCP / metrics: `8001`

## Observability

The workload is expected to:

- expose Prometheus metrics for Model Gateway and MCP/tool execution;
- export OpenTelemetry traces to `trace01`;
- preserve structured lifecycle logs;
- preserve cross-process `run_id` correlation.

Tempo OTLP endpoint:

- `trace01` / `192.168.10.20:4317`

Prometheus scraping will be provided by `mon01`.

## Dependencies

agent01 depends on:

- pve01
- local-lvm
- LAN connectivity
- OPNsense for gateway/DNS
- outbound access to the configured model provider

Observability integrations use:

- mon01 for Prometheus/Grafana
- trace01 for Tempo

Loss of observability services should not by itself make the Agent Platform
application workload unavailable.

## Recovery goal

agent01 is intended to be reproducible from Git-managed infrastructure and
deployment configuration.

The M5 experiment will validate:

- automatic startup;
- automatic process recovery;
- versioned rollout;
- secure runtime configuration;
- health verification;
- observability continuity;
- tested rollback.

The final deployment architecture remains experimental until the Evidence-Gated
Architecture decision is completed.
