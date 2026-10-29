# Compute Architecture

## Purpose

This document describes how compute resources are organized in the homelab,
how virtual workloads are expected to run, and which reliability constraints
currently apply.

## Primary compute node

The current platform has one primary compute node:

`pve01`

`pve01` runs Proxmox VE and acts as the virtualization layer for the homelab.

```text
Physical host
    |
    v
  pve01
 Proxmox VE
    |
    +-- CT 100 - mon01 (observability)
    +-- CT 101 - trace01 (distributed tracing)
    +-- CT 102 - agent01 (agent runtime)
    +-- VM 103 - inference01 (GPU inference)
    +-- VM 104 - ha01 (Home Assistant)
    +-- VM 105 - gtnh01 (stopped)
    +-- future infrastructure workloads
    +-- future application workloads
```

## Hardware

Current `pve01` hardware:

- Motherboard: ASUS PRIME Z390M-PLUS
- BIOS: 3006
- CPU: Intel Core i7-9700K
- CPU topology: 8 cores / 8 threads
- RAM: 24 GiB DDR4
- NIC: Intel I219-V
- Network link: 1 Gbps full duplex
- Power supply: Corsair RM750x
- Inference GPU: NVIDIA GeForce RTX 3060, 12 GiB (`01:00.0`)
- Display GPU: NVIDIA GeForce GT 610 (`03:00.0`)
- Virtualization extensions: enabled
- VT-d / IOMMU: enabled

## Hypervisor responsibilities

Proxmox VE is responsible for:

- LXC lifecycle;
- VM lifecycle;
- storage abstraction;
- guest startup ordering;
- backup scheduling;
- guest shutdown orchestration;
- workload placement on local storage.

## Current infrastructure workloads

Guests that provide platform infrastructure:

| Guest | VMID | Type | Role |
|---|---|---|---|
| `mon01` | 100 | LXC | Monitoring and observability |
| `inference01` | 103 | QEMU VM | Local model inference |

`mon01` is described in the next section. `inference01` is described under
[inference01 resource allocation](#inference01-resource-allocation) and in
[Inference](inference.md).

Further guests are versioned under `proxmox/pve01/guests/`.

## mon01 resource allocation

Current allocation:

- 2 vCPU
- 4 GiB RAM
- 512 MiB swap
- 32 GB disk
- storage: `local-lvm`

`mon01` is intentionally lightweight because its current workload consists
primarily of infrastructure monitoring services.

## inference01 resource allocation

Current allocation:

- 4 vCPU (`cpu: host`)
- 8 GiB RAM, memory ballooning disabled
- 64 GB disk on `local-lvm`, `virtio-scsi-single`
- `q35` machine type, OVMF firmware
- GPU passthrough: `hostpci0` `0000:01:00.0`, `hostpci1` `0000:01:00.1`
- network: `virtio` on `vmbr0`
- guest agent: enabled

`inference01` owns the only compute GPU in the homelab. It serves an
OpenAI-compatible inference endpoint used by `agent01` and by developer
workstations.

## Container model

`mon01` is an unprivileged LXC container.

Nesting is currently disabled.

This configuration is preferred while the current services do not require
nested container capabilities.

## Startup orchestration

Proxmox guest startup ordering is used to define infrastructure startup
precedence.

Current `mon01` policy:

```text
onboot = true
order = 10
startup delay = 30 seconds
shutdown timeout = 60 seconds
```

Current `inference01` policy:

```text
onboot = true
order = 40
startup delay = 30 seconds
shutdown timeout = 60 seconds
```

`inference01` starts later than `mon01` because it is a consumer of platform
infrastructure rather than a foundation service.

The desired state is versioned under:

```text
proxmox/pve01/guests/mon01.yml
proxmox/pve01/guests/inference01.yml
```

Current planned ordering convention:

```text
10 - monitoring / foundational infrastructure
20 - core infrastructure services
30 - stateful services
40 - application services
50 - optional workloads
```

Intervals of ten are intentionally used so new dependencies can be inserted
later without renumbering the complete startup graph.

## Startup validation

A real `pve01` reboot has been executed.

The following sequence was validated:

```text
pve01 power on
      |
      v
Proxmox boot
      |
      v
pve-guests.service
      |
      v
CT 100 / mon01
      |
      +-- Prometheus active
      +-- Grafana active
      +-- ntfy active
```

No manual guest start was required.

## Shutdown architecture

The host uses Proxmox guest shutdown orchestration.

The operational shutdown script is:

```text
scripts/shutdown-homelab.sh
```

The script requests a graceful host shutdown rather than force-stopping
containers directly.

Expected sequence:

```text
shutdown request
       |
       v
systemd / Proxmox
       |
       v
guest shutdown
       |
       v
host poweroff
```

## Compute reliability

There is currently no compute redundancy.

`pve01` is a single physical failure domain.

If `pve01` becomes unavailable:

- `mon01` becomes unavailable;
- Prometheus becomes unavailable;
- Grafana becomes unavailable;
- ntfy becomes unavailable;
- future workloads hosted on `pve01` will also become unavailable.

High availability is not currently implemented.

## Thermal limitation

The current CPU cooling solution is insufficient for sustained heavy CPU
workloads.

Stress testing has resulted in CPU temperatures around:

`92-94 C`

with thermal throttling.

Until the cooling solution is upgraded:

- sustained stress workloads should be avoided;
- sustained CPU-heavy AI workloads should be avoided;
- thermal monitoring must remain enabled.

## Display configuration

The GT 610 at `03:00.0` is used for the host console only. It is not used for
compute.

The RTX 3060 is bound to `vfio-pci` and is not available to the host. The
`nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` and `nouveau` modules are
blacklisted through `blacklist-gpu-passthrough.conf` so the device can be
assigned to `inference01`.

The host keeps a persistent `nomodeset` GRUB configuration because the display
GPU has no usable accelerated driver under Proxmox.

This is considered a temporary compatibility measure rather than a long-term
platform requirement.

## Future compute direction

Potential future architecture:

```text
                homelab
                  |
       +----------+----------+
       |                     |
     pve01                 node02
 primary compute       independent node
       |                     |
 workloads             backup / utility
```

Possible future capabilities include:

- second physical node;
- dedicated backup node;
- Proxmox Backup Server;
- K3s;
- distributed workloads;
- external monitoring;
- workload migration;
- infrastructure service separation.
