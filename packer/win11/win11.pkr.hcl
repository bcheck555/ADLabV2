packer {
  required_version = ">= 1.9.0"
  required_plugins {
    hyperv = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/hyperv"
    }
  }
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

  cd_files  = ["${path.root}/http/autounattend.xml"]
  cd_label  = "UNATTEND"

  boot_wait    = "1s"
  boot_command = ["<enter><wait><enter><wait><enter><wait><enter>"]

  communicator   = "winrm"
  winrm_username = var.winrm_user
  winrm_password = var.winrm_pass
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "2h"

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
