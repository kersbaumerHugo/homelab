# Workload Mode Controller (pve01)

## Scope

`./scripts/workload-mode.sh` manages the mutually exclusive VMs
`103` (`inference01`) and `105` (`gtnh01`). VM `905` is an isolated
restore test; a running VM 905 blocks switching.

`status` and `plan` are read-only. `switch` is **disabled by default**.
Do not enable live switching until the known CPU cooling issue has been
physically inspected/remediated and the operational prerequisites below
have been verified.

## Commands

```bash
./scripts/workload-mode.sh status
./scripts/workload-mode.sh plan gtnh
./scripts/workload-mode.sh plan ai
```

The live command, **only after hardware and VM verification**:

```bash
HOMELAB_SWITCH_ENABLED=1 ./scripts/workload-mode.sh switch gtnh --execute
HOMELAB_SWITCH_ENABLED=1 ./scripts/workload-mode.sh switch ai --execute
```

Switching requires: valid CPU sensor data below 70 C (conservative gate,
not proof of adequate cooling); both VMs present; VM 905 not running;
only one of VMs 103 and 105 running; enough `MemAvailable` for the
requested VM plus a 2 GiB reserve; and exclusive `flock` lock.
No forced `qm stop` is used. 103 and 105 have to support guest agent
for post-start readiness checks, and 105 must have Docker Compose at
`/home/debian/services/gtnh/compose.yaml` with a `gtnh` container
exposing Docker health status.

For GTNH shutdown, the controller runs `docker compose stop --timeout 180`
inside VM 105, checks the guest's exit code, shuts down the VM gracefully,
and confirms it stopped *before* starting VM 103. On GTNH boot it runs
`docker compose up -d` and waits up to 10 minutes for `healthy`.

The inference VM's guest-agent readiness is checked, **not** whether the
model/inference application is healthy. Do not treat the success message
as an application-level SLO or deploy validation.

## Failures and recovery

If source shutdown fails, the target is not started. If target health
fails, the controller attempts graceful shutdown of the target and
leaves the source off; it does **not** automatically restart the source.
If either VM is reported as running unexpectedly or health cannot be
confirmed, use `status`, Proxmox logs, and `qm` manually. Do not start
another VM until the current VM is safely stopped.

The controller only manages 103/105; it does not alter the disabled
`gtnh01-daily` backup schedule and does not remove VM 905. Backup recovery
has been verified at the guest/volume level, but boot of the restored
Minecraft world has not been validated.

## Validation

```bash
bash -n scripts/workload-mode.sh scripts/test-workload-mode.sh
bash scripts/test-workload-mode.sh
./scripts/workload-mode.sh status
./scripts/workload-mode.sh plan gtnh
./scripts/workload-mode.sh plan ai
```

The tests mock `ssh`, `qm`, `sensors`, and `sleep` and therefore cannot
exercise the real guest agent, Docker, or physical cooling.
