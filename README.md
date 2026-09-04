# Homelab

A reliability-oriented homelab built to practice and demonstrate DevOps,
SRE, Platform Engineering and infrastructure operations.

The goal of this repository is not only to store configuration files, but to
make the infrastructure reproducible, observable, recoverable and auditable.

## Engineering principles

The platform is developed around the following principles:

- Git is the source of truth for non-secret desired state.
- Runtime configuration should be reproducible from versioned code.
- Infrastructure changes should be validated before deployment.
- Monitoring must cover both services and the infrastructure that runs them.
- Backups are only considered valid when restore has been tested.
- Configuration drift should be detectable.
- Failure scenarios should be tested deliberately when safe.
- Known risks and technical debt must be documented explicitly.

## Current architecture

```text
                         Internet
                            |
                          Modem
                            |
                         OPNsense
                       192.168.10.1
                            |
                          Switch
                            |
                          pve01
                       192.168.10.10
                  Proxmox VE hypervisor
                    /               \
                   /                 \
              local-lvm           hdd-backup
                SSD                  HDD
                 |                    |
               CT 100              vzdump
               mon01              backups
          192.168.10.162
                 |
        +--------+--------+
        |        |        |
   Prometheus  Grafana   ntfy
```

## Current platform status

| Capability | Status |
|---|---|
| Dedicated firewall | Implemented |
| Proxmox virtualization host | Implemented |
| Monitoring platform | Implemented |
| Infrastructure metrics | Implemented |
| SMART disk monitoring | Implemented |
| LVM monitoring | Implemented |
| Backup monitoring | Implemented |
| Grafana alerting | Implemented |
| ntfy notifications | Implemented |
| Monitoring deployment automation | Implemented |
| Transactional rollback | Implemented |
| CI validation | Implemented |
| Guest boot policy as code | Implemented |
| Backup policy as code | Implemented |
| Backup restore test | Validated |
| Configuration drift detection | Implemented |
| Backup alert failure injection | Validated |
| Graceful shutdown tooling | Implemented |
| Off-host backup | Not implemented |
| Off-site backup | Not implemented |
| External host-down monitoring | Not implemented |

## Current systems

### Network

- LAN: `192.168.10.0/24`
- Gateway: `192.168.10.1`
- Firewall: OPNsense
- DHCP pool: `192.168.10.100-199`

### Compute

Primary virtualization node:

- Hostname: `pve01`
- Management IP: `192.168.10.10`
- Hypervisor: Proxmox VE
- CPU: Intel Core i7-9700K
- RAM: 24 GiB DDR4

### Monitoring

Monitoring runs inside LXC container `mon01`:

- VMID: `100`
- IP: `192.168.10.162`
- OS: Debian 13
- 2 vCPU
- 4 GiB RAM
- 32 GB disk
- Prometheus
- Grafana
- ntfy

### Storage

Primary SSD:

- approximately 512 GB
- Proxmox OS
- `local-lvm`
- VM/LXC storage

Backup HDD:

- approximately 1 TB
- ext4
- Proxmox storage ID: `hdd-backup`
- local vzdump backup destination

## Documentation

Start here:

- [Documentation index](docs/README.md)
- [Architecture](docs/architecture/README.md)
- [Operations](docs/operations/README.md)
- [Runbooks](docs/runbooks/README.md)
- [Architecture Decision Records](docs/adr/README.md)
- [Inventory](inventory/README.md)
- [Documentation status](docs/documentation-status.md)

## Repository structure

```text
.github/        CI workflows
docs/           Architecture, operations, ADRs and runbooks
inventory/      Current hardware and service inventory
monitoring/     Prometheus, Grafana, ntfy and collectors
proxmox/        Proxmox desired state
scripts/        Validation, deployment and operational tooling
ansible/        Reserved for configuration management
tofu/           Reserved for Infrastructure as Code
```

## Operational model

Infrastructure changes should normally follow:

```text
branch
  |
validation
  |
pull request
  |
CI
  |
merge
  |
deployment
  |
runtime verification
```

Manual runtime changes are treated as exceptional operations and should either
be reconciled back to Git or documented explicitly.

## Current reliability boundary

The largest remaining infrastructure risk is the lack of a second physical
failure domain.

Production workloads and the current backup disk are both hosted inside
`pve01`.

The local backup system protects against several logical and storage failures,
but it does not protect against complete loss of the physical host.

Off-host backup is therefore the next major infrastructure reliability
milestone.

## Contribution and change process

See:

[CONTRIBUTING.md](CONTRIBUTING.md)

## Documentation baseline

Current documented baseline:

**2026-09-04**
