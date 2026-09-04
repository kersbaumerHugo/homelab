# Network Architecture

## Purpose

This document describes the current homelab network topology, addressing
model, responsibilities and known limitations.

## Physical topology

```text
                    Internet
                       |
                  ISP connection
                       |
                  Nokia modem
                 192.168.1.254
                       |
                     WAN
                       |
                   OPNsense
                 192.168.10.1
                       |
                     LAN
                       |
                 Ethernet switch
                  /          \
                 /            \
              pve01          clients
         192.168.10.10
                |
              mon01
         192.168.10.162
```

## LAN

Network:

`192.168.10.0/24`

Default gateway:

`192.168.10.1`

DHCP range:

`192.168.10.100-199`

## OPNsense

OPNsense runs on a dedicated physical appliance and acts as the network
gateway and firewall.

Current interface assignment:

| Interface | Role |
|---|---|
| igc0 | WAN |
| igc1 | LAN |
| igc2 | unused / reserved |
| igc3 | unused / reserved |

Physical interface order from left to right:

```text
igc0 | igc1 | igc2 | igc3
```

## Infrastructure addressing

| System | Address | Role |
|---|---|---|
| OPNsense | 192.168.10.1 | Gateway / firewall |
| pve01 | 192.168.10.10 | Proxmox management |
| mon01 | 192.168.10.162 | Monitoring platform |

mon01 uses a DHCP reservation.

## Routing

pve01 and mon01 use OPNsense as their default gateway.

Expected route:

```text
default via 192.168.10.1
```

## Monitoring traffic

Prometheus runs inside mon01 and scrapes pve01 through:

```text
192.168.10.10:9100
```

The monitoring path is therefore:

```text
pve01
  |
Node Exporter
  |
LAN
  |
mon01 / Prometheus
```

## Security boundary

OPNsense is the main network security boundary for the homelab.

Current administrative protections include:

- non-default administrative credentials;
- TOTP;
- configuration backup.

Raw OPNsense configuration exports must not be committed to the public
repository because they may contain sensitive data.

## Dependencies

Current infrastructure connectivity depends on:

- OPNsense;
- Ethernet switch;
- pve01 Ethernet interface;
- physical cabling.

## Known limitations

The current network has no redundancy.

Single points of failure include:

- OPNsense appliance;
- Ethernet switch;
- physical link to pve01.

There is currently no dedicated:

- management VLAN;
- infrastructure VLAN;
- IoT VLAN.

These are accepted limitations at the current platform stage.

## Future direction

Potential future improvements include:

- network segmentation;
- management VLAN;
- IoT VLAN;
- firewall configuration automation;
- redundant switching;
- external connectivity monitoring.
