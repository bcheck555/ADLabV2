variable "vm_name" {
  type    = string
  default = "ws2025-packer-build"
}

variable "iso_path" {
  type    = string
  default = "D:\\LabSources\\ISOs\\26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "output_dir" {
  type    = string
  default = "D:\\CODE\\ADLabV2\\packer\\ws2025\\output"
}

variable "disk_size" {
  type    = number
  default = 61440  # 60 GB in MB
}

variable "memory" {
  type    = number
  default = 4096
}

variable "cpu_count" {
  type    = number
  default = 4
}

variable "switch_name" {
  type    = string
  default = "PackerSwitch"
}

variable "winrm_user" {
  type    = string
  default = "Administrator"
}

variable "winrm_pass" {
  type      = string
  default   = "P@ssw0rd!Lab1"
  sensitive = true
}
