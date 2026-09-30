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
  default = "ws2025-packer-build"
}

variable "iso_path" {
  type    = string
  default = "D:\\LabSources\\ISOs\\Windows_Server_2025_EVAL_x64FRE_en-us.iso"
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

source "hyperv-iso" "ws2025" {
  vm_name               = var.vm_name
  iso_url               = var.iso_path
  iso_checksum          = var.iso_checksum
  output_directory      = var.output_dir
  disk_size             = var.disk_size
  memory                = var.memory
  cpus                  = var.cpu_count
  generation            = 2
  enable_secure_boot    = false
  enable_dynamic_memory = false
  switch_name           = var.switch_name
  guest_additions_mode  = "disable"

  # cd_files injects autounattend.xml for unattended install
  cd_files = ["${path.root}/http/autounattend.xml"]
  cd_label = "UNATTEND"

  boot_wait    = "1s"
  boot_command = ["<enter><wait><enter><wait><enter><wait><enter>"]

  communicator = "ssh"
  ssh_host     = "10.0.0.2"
  ssh_username = var.ssh_user
  ssh_password = var.ssh_pass
  ssh_timeout  = "2h"

  # Sysprep is scheduled by 03-sysprep.ps1 as a one-shot scheduled task.
  # shutdown_command is a no-op; Packer waits for VM power-off from sysprep.
  shutdown_command = "cmd /c echo Waiting for sysprep scheduled task..."
  shutdown_timeout = "30m"
}

build {
  name    = "ws2025-base"
  sources = ["source.hyperv-iso.ws2025"]

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
    script = "${path.root}/scripts/04-move-vhdx.sh"
    environment_vars = [
      "PACKER_OUTPUT_DIR=${var.output_dir}",
      "PACKER_DEST_PATH=D:\\CODE\\ADLabV2\\base-vhds\\ws2025-base.vhdx"
    ]
  }
}
