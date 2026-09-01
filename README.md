# Homelab

Infrastructure-as-code and operational documentation for the homelab.

## Current baseline

### Network
- LAN: 192.168.10.0/24
- Gateway / OPNsense: 192.168.10.1
- DHCP pool: 192.168.10.100-199

### Proxmox
- Node: pve01
- Management IP: 192.168.10.10
- Hypervisor: Proxmox VE
- CPU: Intel Core i7-9700K
- RAM: 24 GB

### Storage
- SSD 512 GB
  - root: 64 GB
  - swap: 8 GB
  - local-lvm: ~334 GB
  - LVM free reserve: ~68 GB
- HDD 1 TB
  - hdd-backup: ~916 GiB ext4

### Monitoring
- mon01 / CT 100
- IP: 192.168.10.162
- Debian 13
- 2 vCPU
- 4 GiB RAM
- 32 GB disk
- Prometheus
- Grafana

### Host telemetry
- node_exporter
- lm-sensors
- smartd
