# pve01 Inventory

## Identity

- Hostname: `pve01`
- Role: primary virtualization host
- Management IP: `192.168.10.10`
- Hypervisor: Proxmox VE

## Hardware

### Motherboard

ASUS PRIME Z390M-PLUS

BIOS:

`3006`

### CPU

Intel Core i7-9700K

- 8 cores
- 8 threads
- VT-x enabled
- VT-d enabled

### Memory

24 GiB DDR4

### Network

Intel I219-V

Linux interface:

`eno1`

Current negotiated link:

- 1 Gbps
- full duplex

### GPU

Temporary NVIDIA GT610

The system currently uses a persistent `nomodeset` GRUB configuration.

### Power supply

Corsair RM750x

### Cooling

Current CPU cooler is an Intel stock radial cooler.

This cooler is not considered adequate for sustained high CPU load.

Stress testing has caused CPU temperature to reach approximately
92-94 C with thermal throttling.

## Storage

### Primary SSD

Model:

`P3-512`

Approximate capacity:

512 GB

Role:

- Proxmox OS
- root filesystem
- local storage
- local-lvm

SMART status:

PASSED

### Backup HDD

Model:

`ST1000DM010-2EP102`

Approximate capacity:

1 TB

Filesystem:

ext4

Label:

`pve-backup`

Mount:

`/mnt/pve/hdd-backup`

Proxmox storage ID:

`hdd-backup`

SMART status:

PASSED

Historical observation:

`Reported_Uncorrectable = 2`

Current relevant SMART state:

- reallocated sectors: 0
- pending sectors: 0
- offline uncorrectable: 0
- CRC errors: 0

## Software telemetry

Installed on the host:

- prometheus-node-exporter
- smartmontools
- lm-sensors

Custom metrics collectors:

- LVM
- SMART
- backup state

## Guest Inventory

### LXC Containers

| VMID | Name    | Status   | Purpose          | Cores | Memory  | RootFS  | Network      |
|------|---------|----------|------------------|-------|---------|---------|---------------|
| 100  | mon01   | running  | Observability    | 2     | 4096 MB | 32 GB   | DHCP (192.168.10.162) |
| 101  | trace01 | running  | Distributed tracing | 2     | 4096 MB | 16 GB   | 192.168.10.20/24 |
| 102  | agent01 | running  | Agent runtime    | 2     | 2048 MB | 16 GB   | 192.168.10.30/24 |

### QEMU VMs

| VMID | Name          | Status   | Purpose        | Cores | Memory  | Boot Disk  | GPU Passthrough |
|------|---------------|----------|----------------|-------|---------|------------|-----------------|
| 103  | inference01   | running  | GPU inference  | 4     | 8192 MB | 64 GB SSD  | RTX 3060 (2x)  |
| 104  | ha01          | running  | Home Assistant | 4     | 4096 MB | 64 GB      | -               |
| 105  | gtnh01        | stopped  | GoldenHugo     | -     | 8192 MB | 40 GB      | -               |

### Purpose Summary

- **mon01**: Observability node (Prometheus, Grafana, node_exporter)
- **trace01**: Distributed tracing backend (Tempo)
- **agent01**: Agent runtime environment (container engine for services)
- **inference01**: GPU-accelerated inference workloads (RTX 3060 passthrough)
- **ha01**: Home Assistant OS automation hub
- **gtnh01**: Stopped GoldenHugo test environment
