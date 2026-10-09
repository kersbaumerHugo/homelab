resource "proxmox_virtual_environment_file" "haos" {
  node_name    = "pve01"
  datastore_id = "local"
  content_type = "import"
  overwrite    = false

  source_file {
    path = "${path.module}/../../.cache/haos/haos_ova-18.3.qcow2"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "proxmox_virtual_environment_vm" "ha01" {
  node_name = "pve01"
  vm_id     = 104
  name      = "ha01"

  description = "Home Assistant OS 18.3 - managed by homelab OpenTofu"

  bios       = "ovmf"
  on_boot    = true
  started    = true
  protection = true

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_file.haos.id
    size         = 64
    discard      = "on"
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = false
  }

  lifecycle {
    prevent_destroy = true
  }
}
