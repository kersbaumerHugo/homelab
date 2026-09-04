# Security Posture

## Purpose

This document describes the current security controls, trust boundaries and
known security gaps in the homelab.

It documents the platform as it exists today and does not imply compliance
with a formal security framework.

## Security principles

The current platform follows these principles:

- secrets should not be committed to the public repository;
- network ingress is controlled through a dedicated firewall;
- administrative access should use strong authentication;
- infrastructure state should be reviewable through Git;
- unnecessary privileges should be avoided;
- unneeded services should be disabled;
- security-relevant technical debt should be documented explicitly.

## Network security boundary

OPNsense is the primary network security boundary.

Topology:

```text
Internet
   |
ISP modem
   |
OPNsense
   |
Homelab LAN
```

OPNsense is physically separate from pve01.

This prevents the main compute host from also being the primary network
security boundary.

## OPNsense administrative controls

Current controls include:

- default/initial administrative password replaced;
- TOTP enabled;
- configuration backup created;
- dedicated WAN and LAN interface assignment.

Raw OPNsense configuration exports must not be committed to the public Git
repository because they may contain sensitive configuration.

## Repository security policy

The Git repository is public.

Therefore the repository must contain only non-secret desired state and
sanitized documentation.

Examples of data that must not be committed:

- passwords;
- API keys;
- private keys;
- tokens;
- exported firewall configuration containing credentials;
- Terraform/OpenTofu state containing secrets;
- application secrets;
- backup encryption keys;
- private certificates.

The `.gitignore` should be treated as a safety control, not as the only
protection against secret exposure.

Changes should be reviewed before push.

## Administrative access

Operational tooling currently accesses pve01 using SSH key authentication.

Automation should avoid embedding credentials inside scripts.

Where possible:

- credentials should remain outside Git;
- automation should use least-privilege identities;
- interactive passwords should not be stored in repository files.

## Proxmox host security

pve01 is a dedicated virtualization host.

Current relevant controls include:

- SSH-based administrative access;
- service-state verification;
- explicit package/repository management;
- OpenIPMI disabled because no supported IPMI hardware is present;
- infrastructure configuration progressively moved into versioned desired
  state.

The decision to disable OpenIPMI is documented under:

```text
docs/adr/0001-disable-openipmi.md
```

## Container isolation

mon01 is an unprivileged LXC container.

Nesting is disabled.

This reduces the privileges granted to the monitoring workload while its
current service requirements do not require nested container behavior.

## Monitoring security model

Prometheus, Grafana and ntfy currently operate on the trusted homelab LAN.

The monitoring stack is not intended to be directly exposed to the public
Internet.

The current design assumes the LAN is a trusted administrative network.

This assumption should be revisited when additional user-facing or IoT
workloads are introduced.

## Alerting

ntfy is self-hosted.

Current notification path:

```text
Grafana
   |
ntfy
   |
homelab-alerts
```

Notification configuration is versioned only where it does not expose secrets.

## CI security value

CI currently provides several security-adjacent controls:

- configuration syntax validation;
- ShellCheck;
- Grafana provisioning validation;
- duplicate UID checks;
- datasource UID checks;
- Prometheus validation;
- Python syntax checks;
- systemd unit validation.

These controls reduce the chance of deploying malformed or unexpected
configuration.

They are not a replacement for dependency scanning, secret scanning or
vulnerability management.

## Current trust model

The current platform effectively trusts:

- the administrative workstation;
- the homelab LAN;
- pve01;
- mon01;
- the Git repository as desired-state source.

The platform currently has limited internal segmentation.

## Current gaps

### No network segmentation

There is currently no dedicated:

- management VLAN;
- infrastructure VLAN;
- IoT VLAN.

As more workloads are added, flat-network trust will become less acceptable.

### No documented centralized secret management

Secrets are intentionally kept out of Git, but a formal secret-management
platform is not yet implemented.

Potential future options include:

- SOPS;
- age;
- Ansible Vault;
- HashiCorp Vault;
- dedicated secret stores.

### No dedicated vulnerability-management process

There is not yet a formal process for:

- dependency vulnerability scanning;
- operating-system vulnerability tracking;
- container image scanning;
- automated patch compliance.

### No external identity provider

Infrastructure authentication is currently local to each relevant system.

Centralized identity and role-based access control have not yet been
implemented.

### Monitoring stack shares the primary host

A compromise or complete loss of pve01 can also remove the local monitoring
and notification stack.

## Public repository considerations

Because the repository is intended to demonstrate engineering practices
publicly, documentation must avoid exposing details that create unnecessary
risk.

Acceptable examples:

- private RFC1918 addresses;
- hardware models;
- architectural diagrams;
- service roles;
- sanitized configuration.

Unacceptable examples:

- credentials;
- secret tokens;
- private-key material;
- recovery codes;
- session cookies;
- raw confidential configuration exports.

## Security roadmap

Near-term priorities:

1. document all trust boundaries;
2. add automated secret scanning;
3. define a patch/update procedure;
4. add network segmentation as new workload classes appear;
5. formalize secret management;
6. introduce external monitoring on a second physical system;
7. evaluate backup encryption for off-host/off-site copies.

## Security status summary

```text
Dedicated firewall             IMPLEMENTED
TOTP on firewall administration IMPLEMENTED
Git review / CI                IMPLEMENTED
Secrets excluded from Git      POLICY IN PLACE
Unprivileged monitoring LXC    IMPLEMENTED
Network segmentation           NOT IMPLEMENTED
Central secret management      NOT IMPLEMENTED
Vulnerability management       NOT IMPLEMENTED
Centralized identity           NOT IMPLEMENTED
External security monitoring   NOT IMPLEMENTED

```
