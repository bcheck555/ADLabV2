packer {
  required_version = ">= 1.9.0"
  required_plugins {
    hyperv = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

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
  default = 61440
}

variable "memory" {
  type    = number
  default = 8192
}

variable "cpu_count" {
  type    = number
  default = 8
}

variable "switch_name" {
  type    = string
  default = "PackerSwitch"
}

variable "ssh_user" {
  type    = string
  default = "Administrator"
}

variable "ssh_pass" {
  type      = string
  default   = "P@ssw0rd!Lab1"
  sensitive = true
}

source "hyperv-iso" "win11" {
  vm_name              = var.vm_name
  iso_url              = var.iso_path
  iso_checksum         = var.iso_checksum
  output_directory     = var.output_dir
  disk_size            = var.disk_size
  memory               = var.memory
  cpus                 = var.cpu_count
  generation           = 2
  enable_secure_boot   = false
  enable_dynamic_memory = false
  switch_name          = var.switch_name
  guest_additions_mode = "disable"

  cd_files  = ["${path.root}/http/autounattend.xml", "${path.root}/http/OpenSSH-Win64-v9.5.0.0.msi", "${path.root}/http/PowerShell-7.6.0-win-x64.msi"]
  cd_label  = "UNATTEND"

  boot_wait    = "1s"
  boot_command = ["<enter><wait><enter><wait><enter><wait><enter>"]

  communicator = "ssh"
  ssh_host     = "10.0.0.2"
  ssh_username = var.ssh_user
  ssh_password = var.ssh_pass
  ssh_timeout  = "2h"

  shutdown_command = "cmd /c echo Waiting for sysprep scheduled task..."
  shutdown_timeout = "30m"
}

build {
  name    = "win11-base"
  sources = ["source.hyperv-iso.win11"]

  provisioner "powershell" {
    script = "${path.root}/scripts/01-init.ps1"
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/02-configure.ps1"
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/03-sysprep.ps1"
  }

  post-processor "shell-local" {
    inline = [
      "powershell -Command \"$src = Get-ChildItem '${var.output_dir}' -Filter '*.vhdx' -Recurse | Select-Object -First 1; if ($src) { $dest = 'D:\\CODE\\ADLabV2\\base-vhds\\win11-base.vhdx'; New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null; Move-Item $src.FullName $dest -Force; Write-Host ('Moved ' + $src.Name + ' to win11-base.vhdx'); Remove-Item '${var.output_dir}' -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Error 'No VHDX found in output directory' }\""
    ]
  }
}
