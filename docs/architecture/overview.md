# Architecture Overview

## Purpose

The homelab is a small infrastructure platform designed to provide a
controlled environment for experimenting with DevOps, SRE, Platform
Engineering, observability, infrastructure automation and local AI
workloads.

Reliability and reproducibility are treated as platform requirements
rather than optional improvements.

## Physical topology

```text
Internet
   |
ISP modem
   |
OPNsense
192.168.10.1
   |
Ethernet switch
   |
   +----------------------+
   |                      |
pve01                  clients
192.168.10.10

OPNsense is the network gateway and firewall.

pve01 is currently the primary compute node.

Compute topology
pve01
Proxmox VE
|
+-- CT 100: mon01
|   |
|   +-- Prometheus
|   +-- Grafana
|   +-- ntfy
|
+-- future workloads

mon01 is the first infrastructure container and hosts the current
observability stack.

Future workloads should use explicit Proxmox startup ordering.

Current startup policy:

order 10 -> mon01
order 20 -> future core infrastructure
order 30 -> future stateful services
order 40 -> applications
order 50 -> optional workloads
Storage topology
pve01
|
+-- 512 GB SSD
|   |
|   +-- Proxmox OS
|   +-- local
|   +-- local-lvm
|
+-- 1 TB HDD
    |
    +-- hdd-backup
        |
        +-- Proxmox vzdump backups

The backup disk is physically separate from the primary SSD but remains
inside the same physical host.

It therefore provides storage-level separation but not host-level
failure-domain separation.

Observability architecture
pve01
|
+-- node_exporter
|   |
|   +-- system metrics
|   +-- filesystem metrics
|   +-- hwmon / temperatures
|   +-- textfile collector
|       |
|       +-- LVM collector
|       +-- SMART collector
|       +-- backup collector
|
+------------------------------+
                               |
                               v
                            mon01
                               |
                          Prometheus
                               |
                            Grafana
                               |
                              ntfy

The platform currently monitors:

CPU
memory
filesystem usage
CPU temperature
LVM thin-pool data usage
LVM thin-pool metadata usage
SMART disk health
disk temperature
SMART error counters
backup job state
backup artifact presence
backup freshness
collector freshness
Configuration flow
Git repository
      |
      v
validation
      |
      v
deployment scripts
      |
      v
runtime
      |
      v
verification

Monitoring deployment is transactional.

When deployment fails after runtime changes begin, the deployment tooling
attempts to restore the previous configuration.

Backup architecture

Current backup path:

mon01
  |
vzdump snapshot
  |
zstd compression
  |
hdd-backup

The backup job is versioned in Git and deployed through automation.

Current schedule:

03:00 daily

Retention:

7 daily
4 weekly
3 monthly

A complete restore drill has been executed successfully by restoring the
backup into temporary CT 900.

The temporary container was tested and later destroyed.

Failure domains

The current architecture has one major limitation:

+---------------- pve01 ----------------+
|                                       |
| primary SSD             backup HDD    |
|     |                       |         |
| workloads                 backups     |
|                                       |
+---------------------------------------+

The primary workloads and backup storage remain inside the same physical
machine.

Loss of the entire host may therefore cause simultaneous loss of both
the workload and its local backup.

A second physical system is required before off-host backup can be
implemented.

Security boundaries

Secrets and exported device configuration files must not be committed to
the public repository.

Sensitive runtime configuration is treated separately from non-secret
desired state.

OPNsense configuration backups, credentials, tokens and similar
artifacts must remain outside Git unless appropriately sanitized.

Current architectural direction

The next major infrastructure capability is a physically independent
backup target.

Longer-term platform evolution may include:

Proxmox Backup Server
external availability monitoring
configuration management with Ansible
Infrastructure as Code with OpenTofu
additional compute nodes
Kubernetes/K3s
GitOps
local AI workloads
