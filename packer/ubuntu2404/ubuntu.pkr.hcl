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
  default = "ubuntu2404-packer-build"
}

variable "iso_path" {
  type    = string
  default = "D:\\LabSources\\ISOs\\ubuntu-24.04.2-live-server-amd64.iso"
}

variable "iso_checksum" {
  type    = string
  # SHA256 of ubuntu-24.04.2-live-server-amd64.iso
  # Verify at: https://releases.ubuntu.com/24.04/SHA256SUMS
  default = "sha256:d6dab0c3a657988501b4bd76f1297c8ae2bde9c9519a59dce03e21eeb79bcb41"
}

variable "output_dir" {
  type    = string
  default = "D:\\CODE\\ADLabV2\\packer\\ubuntu2404\\output"
}

variable "disk_size" {
  type    = number
  default = 40960  # 40 GB in MB
}

variable "memory" {
  type    = number
  default = 2048
}

variable "cpu_count" {
  type    = number
  default = 2
}

variable "switch_name" {
  type    = string
  default = "PackerSwitch"
}

variable "ssh_user" {
  type    = string
  default = "labadmin"
}

variable "ssh_pass" {
  type      = string
  default   = "P@ssw0rd!Lab1"
  sensitive = true
}

source "hyperv-iso" "ubuntu2404" {
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

  # Ubuntu autoinstall cloud-init user-data
  # Served via Packer's built-in HTTP server
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz quiet autoinstall ds=nocloud-net\\;s=http://{{.HTTPIP}}:{{.HTTPPort}}/ ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter><wait>"
  ]
  boot_wait   = "5s"
  http_directory = "${path.root}/http"

  communicator    = "ssh"
  ssh_username    = var.ssh_user
  ssh_password    = var.ssh_pass
  ssh_timeout     = "30m"
  ssh_handshake_attempts = 50

  shutdown_command = "sudo systemctl poweroff"
  shutdown_timeout = "15m"
}

build {
  name    = "ubuntu2404-base"
  sources = ["source.hyperv-iso.ubuntu2404"]

  provisioner "shell" {
    script = "${path.root}/scripts/01-init.sh"
  }

  provisioner "shell" {
    script = "${path.root}/scripts/02-configure.sh"
  }

  post-processor "shell-local" {
    inline = [
      "powershell -Command \"$src = Get-ChildItem '${var.output_dir}' -Filter '*.vhdx' -Recurse | Select-Object -First 1; if ($src) { $dest = 'D:\\CODE\\ADLabV2\\base-vhds\\ubuntu2404-base.vhdx'; New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null; Move-Item $src.FullName $dest -Force; Write-Host ('Moved ' + $src.Name + ' to ubuntu2404-base.vhdx'); Remove-Item '${var.output_dir}' -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Error 'No VHDX found in output directory' }\""
    ]
  }
}
