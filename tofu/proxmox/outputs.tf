output "ha01_vmid" {
  value = proxmox_virtual_environment_vm.ha01.vm_id
}

output "ha01_node" {
  value = proxmox_virtual_environment_vm.ha01.node_name
}

output "ha01_name" {
  value = proxmox_virtual_environment_vm.ha01.name
}
