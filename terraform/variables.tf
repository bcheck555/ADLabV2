variable "host_user" {
  type        = string
  description = "Username for Hyper-V host WinRM connection (local admin)"
  default     = "Administrator"
}

variable "host_password" {
  type        = string
  description = "Password for Hyper-V host WinRM connection"
  sensitive   = true
}

variable "vm_dir" {
  type        = string
  description = "Directory on the Hyper-V host where ADLabV2 VM disks are stored"
  default     = "E:\\Hyper-V\\Virtual Hard Disks\\ADLabV2"
}

variable "base_vhd_dir" {
  type        = string
  description = "Directory containing Packer-built base VHDXs"
  default     = "E:\\Hyper-V\\Virtual Hard Disks\\ADLabV2\\Base Images"
}

variable "switch_name" {
  type        = string
  description = "Hyper-V virtual switch for lab VMs"
  default     = "LabNAT"
}

variable "ws2025_base_vhdx" {
  type        = string
  description = "Path to WS2025 base VHDX (Packer output)"
  default     = "E:\\Hyper-V\\Virtual Hard Disks\\ADLabV2\\Base Images\\ws2025-base.vhdx"
}

variable "win11_base_vhdx" {
  type        = string
  description = "Path to Win11 base VHDX (Packer output)"
  default     = "E:\\Hyper-V\\Virtual Hard Disks\\ADLabV2\\Base Images\\win11-base.vhdx"
}

variable "ubuntu2404_base_vhdx" {
  type        = string
  description = "Path to Ubuntu 24.04 base VHDX (Packer output)"
  default     = "E:\\Hyper-V\\Virtual Hard Disks\\ADLabV2\\Base Images\\ubuntu2404-base.vhdx"
}
