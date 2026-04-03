variable "vm_name" {
  type    = string
  default = "win11-packer-build"
}

variable "iso_path" {
  type    = string
  default = "D:\\LabSources\\ISOs\\26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "output_dir" {
  type    = string
  default = "D:\\CODE\\ADLabV2\\packer\\win11\\output"
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
