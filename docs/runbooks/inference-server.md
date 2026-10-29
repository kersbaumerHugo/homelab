# Inference Server Runbook

## Purpose

Operational procedures for the `llama-server` instance on `inference01`.

Use this runbook to:

- verify the service is healthy;
- inspect the effective context and slot configuration;
- change context size or slot count;
- revert a configuration change;
- confirm the service recovered.

For design and placement, see [Inference](../architecture/inference.md).

## Prerequisites

- SSH access to `inference01` as `hugo`, or root access to `pve01` with the
  QEMU guest agent enabled on VM 103;
- the bearer token from `/etc/llama-server/api.key`
  (readable by `root` and group `llama`);
- `curl` from any host on `192.168.10.0/24`.

`sudo` on `inference01` requires a password. Guests that only need to use the
API do not need root.

## Service layout

| Path | Purpose |
|---|---|
| `/etc/systemd/system/llama-server.service` | base unit |
| `/etc/systemd/system/llama-server.service.d/override.conf` | GPU readiness gate |
| `/etc/systemd/system/llama-server.service.d/context.conf` | context and slots |
| `/etc/llama-server/api.key` | bearer token |
| `/var/lib/llama-server/models/` | GGUF models, `llama`-owned, mode 700 |

The server binds `192.168.10.40:8080` only. It does not listen on loopback, so
`curl http://127.0.0.1:8080` from inside the VM fails by design.

## Health check

Run from any client:

```bash
curl -sS http://192.168.10.40:8080/health
```

Expected while starting:

```json
{"error":{"message":"Loading model","type":"unavailable_error","code":503}}
```

Expected when ready:

```json
{"status":"ok"}
```

Model load takes roughly one to two minutes after a restart.

## Inspect effective configuration

Authenticated request:

```bash
TOKEN=$(grep '^LOCAL_MODEL_API_KEY=' /path/to/agent-platform/.env | cut -d= -f2-)

curl -sS http://192.168.10.40:8080/props \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{n_ctx: .default_generation_settings.n_ctx, slots: .total_slots}'
```

Expected for the current configuration:

```json
{"n_ctx": 32768, "slots": 4}
```

`n_ctx` is the per-request context. It equals the `-c` value divided by
`--parallel`.

Check slot occupancy before restarting, so no request is interrupted:

```bash
curl -sS http://192.168.10.40:8080/slots \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.[] | {id, n_ctx, is_processing}'
```

All slots report `is_processing: false` when the server is idle.

## Verify GPU usage

On `inference01`:

```bash
nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free \
  --format=csv
```

Expected with `-c 131072 --parallel 4`:

```text
NVIDIA GeForce RTX 3060, 12288 MiB, ~9400 MiB, ~2500 MiB
```

The model itself occupies about 5.6 GiB. The remainder is KV cache and compute
buffers. If usage approaches the total, reduce `-c` before restarting.

## Change context or slots

Context per request is:

```text
n_ctx_per_request = -c / --parallel
```

The KV pool is preallocated at startup, so changing `-c` changes VRAM use. Keep
the product of the two values within roughly 128k tokens on this GPU.

Edit the drop-in, not the base unit:

```bash
sudoedit /etc/systemd/system/llama-server.service.d/context.conf
```

Change only these two lines:

```text
-c 131072 \
--parallel 4 \
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl restart llama-server
```

`restart` terminates in-flight requests. Confirm all slots are idle first.

Then verify with the health check and the `props` request above.

## Revert the tuning drop-in

This removes the context and slot override and returns to the base unit values
(`-c 16384`, automatic slot count):

```bash
sudo rm /etc/systemd/system/llama-server.service.d/context.conf
sudo systemctl daemon-reload
sudo systemctl restart llama-server
```

The base unit is never modified by tuning, so this is the complete rollback.

## Rotate the API token

Not yet exercised on this platform. Treat as theoretical until validated.

```bash
sudo sh -c 'head -c 32 /dev/urandom | od -An -tx1 | tr -d " \n" > /etc/llama-server/api.key'
sudo chown root:llama /etc/llama-server/api.key
sudo chmod 640 /etc/llama-server/api.key
sudo systemctl restart llama-server
```

Every client must be updated in the same window, including
`agent-platform/.env` and any workstation OpenCode configuration.

## Troubleshooting

| Symptom | Check |
|---|---|
| `503 Loading model` | wait; the model reloads in one to two minutes |
| Connection refused | VM 103 running (`qm status 103`), service active |
| `401 Unauthorized` | token mismatch between client and `/etc/llama-server/api.key` |
| `400` on long prompts | prompt exceeds `n_ctx` per request; raise `-c`/`--parallel` ratio |
| First token very slow | prompt evaluation; check prompt tokens in the response usage |
| Empty content with `finish_reason: length` | output budget consumed by `reasoning_content`; raise the client output limit |
| Tool calls ignored | `--jinja` missing from `ExecStart` |

## Success criteria

- `/health` returns `{"status":"ok"}`.
- `/props` reports the intended `n_ctx` and slot count.
- VRAM use leaves at least ~2 GiB free.
- A tool-calling request returns `finish_reason: tool_calls`.
- A prompt larger than the previous context limit is accepted.

## Validation status

The health check, `props` inspection, slot inspection, context change, revert
content, and long-prompt acceptance were exercised on 2026-10-29.

Token rotation and recovery after a full `pve01` reboot were not exercised.
