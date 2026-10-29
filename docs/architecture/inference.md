# Inference

## Purpose

This document describes the local model inference workload: where it runs,
which hardware it owns, how it is exposed, and which reliability constraints
apply.

It does not describe how to operate or change the service. Use the
[inference server runbook](../runbooks/inference-server.md) for that.

## Placement

Inference runs in a dedicated QEMU virtual machine:

| Property | Value |
|---|---|
| Guest | `inference01` |
| VMID | 103 |
| Host | `pve01` |
| Address | `192.168.10.40` |
| vCPU | 4 (`cpu: host`) |
| Memory | 8 GiB, ballooning disabled |

The VM is versioned as desired state under
`proxmox/pve01/guests/inference01.yml`.

## Hardware path

The workload owns the only compute GPU in the homelab: an NVIDIA GeForce
RTX 3060 with 12 GiB of VRAM.

```text
pve01
  |
  +-- 01:00.0 / 01:00.1  RTX 3060 (bound to vfio-pci on the host)
        |
        v
      inference01 (VM 103)
        |
        +-- NVIDIA driver and CUDA toolkit
        +-- llama-server
```

The GPU is assigned with `hostpci0` and `hostpci1` and is unavailable to the
host. The GT 610 at `03:00.0` remains the host console device and is not used
for inference. See [Compute](compute.md#display-configuration).

Passthrough means the VM is a hard boundary: restarting or losing the VM also
removes the inference capacity, and the host cannot use the GPU as a fallback.

## Software stack

| Component | Value |
|---|---|
| Runtime | `llama.cpp` `llama-server` |
| Version | `0.4.1-dev`, build 10987 |
| Service | `llama-server.service` |
| Model | `qwen3.5-9b-q4_k_m.gguf` |
| Model alias | `qwen3.5-9b-local` |
| Quantization | `Q4_K_M`, 8.95 B parameters, 5.6 GB |
| Endpoint | `http://192.168.10.40:8080/v1` |
| Authentication | bearer token from `/etc/llama-server/api.key` |
| Built-in web UI | disabled (`--no-webui`) |

The server runs with `--jinja`, which is required for the model's tool-calling
chat template. Without it the endpoint answers in plain text and ignores tool
definitions.

## Capacity

The server is started with a shared context pool and fixed slot count:

```text
-c 131072 --parallel 4
```

That yields:

- 32768 tokens of context per request;
- 4 concurrent request slots;
- approximately 9.4 GiB of VRAM in use, of 12 GiB available.

Measured on this hardware:

- prompt evaluation: roughly 630 to 1570 tokens per second, depending on prompt
  length;
- token generation: roughly 50 tokens per second.

Prompt evaluation dominates latency. A 32k-token prompt costs tens of seconds
before the first generated token, so larger per-request context has a real
interaction cost even when VRAM allows it.

## Clients

The endpoint is OpenAI-compatible and is consumed by:

- `agent01` through the agent platform `LocalOpenAIModelAdapter`;
- developer workstations through OpenCode;
- optionally, a third-party chat front-end such as Open WebUI.

Clients are not authenticated as separate principals. The single bearer token is
shared, so the endpoint cannot attribute usage to a caller.

## Failure domain

Inference is a single failure domain with no redundancy:

- one GPU;
- one VM;
- one model process;
- one token.

Losing any of them removes inference for every client. There is no cloud
fallback configured at the platform level, so agents that require a model fail
rather than degrade.

## Limitations

- The GPU is committed to passthrough, so the host has no accelerated path.
- The model's trained context is larger than the configured pool; context is
  bounded by VRAM and by prompt-evaluation latency, not by the model.
- The endpoint has no per-client isolation, quota, or usage accounting.
- The token is a single shared secret.
