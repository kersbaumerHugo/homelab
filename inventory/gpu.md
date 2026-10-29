# GPU Inventory

## Purpose

This document tracks all GPU passthrough configurations on `pve01`.

## Current State

### Physical GPU

- **Model**: NVIDIA GeForce RTX 3060
- **PCIe Address**: `0000:01:00.0`
- **Function 0**: Primary GPU (inference)
- **Function 1**: Secondary GPU (reserved/future use)
- **VRAM**: 6 GB GDDR6
- **Status**: Active passthrough to `inference01`

### Passthrough Configuration

#### inference01 (VM 103)

```yaml
vmid: 103
name: inference01
hostpci0: 0000:01:00.0,pcie=1
hostpci1: 0000:01:00.1,pcie=1
```

#### GPU Allocation

- **Primary GPU** (`0000:01:00.0`): Passthrough to VM 103 (`inference01`)
- **Secondary GPU** (`0000:01:00.1`): Also passthrough to VM 103 (`inference01`)

#### Purpose

- Distributed inference workloads
- AI model serving
- GPU-accelerated workloads

## Historical Note

The system previously used a temporary NVIDIA GT610. This has been replaced with the RTX 3060.
