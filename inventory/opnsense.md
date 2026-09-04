# OPNsense Inventory

## Role

Dedicated firewall and network gateway.

## Hardware

Mini PC appliance.

### CPU

Intel N5105

### Memory

8 GB

### Storage

128 GB NVMe

### Network interfaces

4 x Intel 2.5 GbE

Physical interface mapping:

```text
left to right

igc0
igc1
igc2
igc3

Current assignment:

WAN: igc0
LAN: igc1
Network

LAN:

192.168.10.0/24

Gateway:

192.168.10.1

DHCP:

enabled

Pool:

192.168.10.100-199

Upstream

ISP modem:

192.168.1.254

Security

Administrative root password changed from initial state.

TOTP enabled.

A configuration backup has been created.

Repository policy

The raw OPNsense config.xml must not be committed to the public Git
repository because it may contain sensitive configuration.
