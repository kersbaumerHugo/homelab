# agent01 Inventory

## Identity

- Hostname: `agent01`
- Proxmox VMID: `102`
- Type: LXC
- Role: supervised coding execution host / container sandbox candidate
- IP: `192.168.10.30`

## Operating system

Debian 13.

## Resources

- 2 vCPU
- 2 GiB RAM
- 512 MiB swap
- 16 GiB root disk
- storage: `local-lvm`

## Container configuration

- unprivileged: yes
- nesting: enabled
- keyctl: enabled
- automatic startup: enabled
- startup order: 30
- startup delay: 15 seconds
- shutdown timeout: 60 seconds
- `/dev/kvm`: not exposed

`nesting` and `keyctl` are enabled because `agent01` hosts Docker inside the
unprivileged LXC.

## Network

- bridge: `vmbr0`
- IPv4: `192.168.10.30/24`
- gateway: `192.168.10.1`

## Container runtime

Docker Engine is the current container runtime candidate.

Desired engine version:

```text
29.8.1
```

Runtime expectations:

- Docker service enabled and active
- overlayfs storage driver
- systemd cgroup driver
- cgroup v2
- seccomp available
- nested containers operational

The Docker daemon is an infrastructure dependency. Per-execution sandbox policy
belongs to the Agent Platform.

## Security role

`agent01` is not a trusted publication authority.

Its purpose is to execute untrusted or semi-trusted coding workloads behind an
explicit execution boundary.

The intended trust separation remains:

```text
Coding Agent
!= Verification Authority
!= Trusted Publisher
!= Merge Authority
```

M12 established that a plain supervised subprocess is insufficient isolation:
it can access host files, inherited environment, local sockets, and host
networking.

A hardened Docker container inside this unprivileged LXC is therefore being
evaluated as the next execution-boundary candidate.

This inventory entry does not declare Docker isolation accepted. Acceptance
requires Agent Platform M12.3 evidence.

## Declarative sources

```text
proxmox/pve01/guests/agent01.yml
scripts/deploy-agent01.sh
scripts/deploy-agent01-runtime.sh
scripts/verify-agent01.sh
```

## Recovery

```text
scripts/deploy-agent01.sh
scripts/deploy-agent01-runtime.sh
scripts/verify-agent01.sh
```

The guest and non-secret runtime configuration are expected to be reproducible
from Git-managed desired state.

## Validation evidence

Validated manually on 2026-09-18:

- Debian 13 LXC operational
- LXC unprivileged
- `nesting=1`
- `keyctl=1`
- Docker Engine `29.8.1`
- overlayfs
- systemd cgroups / cgroup v2
- seccomp available
- `hello-world` executes successfully
- hardened test container accepts:
  - `--network none`
  - `--read-only`
  - `--cap-drop ALL`
  - `no-new-privileges`
  - PID, memory, and CPU limits
  - non-root UID/GID

## Known limitations

```text
Proxmox host
└── unprivileged LXC
    └── Docker container
```

This is not a microVM boundary. Both container layers ultimately share the
Proxmox host kernel. M12.3 must therefore accept or reject this candidate from
measured security properties rather than assuming VM-equivalent isolation.
