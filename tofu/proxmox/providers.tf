variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
  default     = "https://192.168.10.10:8006/"
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
}
