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
