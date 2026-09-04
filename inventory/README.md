# Homelab Inventory

This directory documents the physical and logical systems that currently
exist.

Inventory describes reality.

Infrastructure code describes desired state.

Architecture documentation explains how the systems interact.

## Current inventory

### [OPNsense](opnsense.md)

Role:

Dedicated firewall and network gateway.

Key responsibilities:

- WAN/LAN boundary;
- routing;
- DHCP;
- administrative network security boundary.

### [pve01](pve01.md)

Role:

Primary Proxmox virtualization host.

Key responsibilities:

- compute;
- local-lvm;
- host telemetry;
- local backup storage;
- guest lifecycle.

### [mon01](mon01.md)

Role:

Monitoring and observability LXC.

Services:

- Prometheus;
- Grafana;
- ntfy.

## Inventory update rule

Update inventory when:

- hardware changes;
- IP addresses change;
- storage devices change;
- guest resources change materially;
- system roles change;
- a system is added or decommissioned.

## Inventory security rule

Do not include:

- credentials;
- serial numbers when unnecessary;
- private keys;
- secret tokens;
- recovery material.

Hardware models and RFC1918 addresses are acceptable for the current public
documentation model.
