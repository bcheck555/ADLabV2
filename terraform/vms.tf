# vms.tf — All lab VMs defined as OpenTofu resources.
#
# Each VM gets an independent dynamic VHDX copied from the appropriate base image.
# Static IPs are NOT set here — Ansible sets them on first run.
# This keeps OpenTofu focused on VM lifecycle, Ansible on configuration.
#
# Note: tofu destroy does NOT delete the VHDX files (null_resource has no destroy
# provisioner). Run Destroy-Lab.ps1 for full cleanup including disk files.

locals {
  # Map base type to base VHDX path
  base_vhds = {
    ws2025    = var.ws2025_base_vhdx
    win11     = var.win11_base_vhdx
    ubuntu    = var.ubuntu2404_base_vhdx
  }

  vms = {
    git01 = { cpu = 4, ram_gb = 8,  base = "ubuntu", disk_gb = 40 }
    dc01  = { cpu = 4, ram_gb = 8,  base = "ws2025", disk_gb = 60 }
    dc02  = { cpu = 4, ram_gb = 8,  base = "ws2025", disk_gb = 60 }
    ca01  = { cpu = 4, ram_gb = 8,  base = "ws2025", disk_gb = 60 }
    db01  = { cpu = 8, ram_gb = 32, base = "ws2025", disk_gb = 100 }
    web01 = { cpu = 4, ram_gb = 8,  base = "ws2025", disk_gb = 60 }
    wks01 = { cpu = 4, ram_gb = 8,  base = "win11",  disk_gb = 60 }
    wks02 = { cpu = 4, ram_gb = 8,  base = "win11",  disk_gb = 60 }
    vmm01 = { cpu = 4, ram_gb = 16, base = "ws2025", disk_gb = 60 }
  }
}

# Independent dynamic VHDXs — one per VM, copied from the appropriate base image.
# Copies can be created in parallel (no shared parent lock).
resource "null_resource" "vm_disk" {
  for_each = local.vms

  triggers = {
    path   = "${var.vm_dir}\\${upper(each.key)}\\${upper(each.key)}.vhdx"
    source = local.base_vhds[each.value.base]
    size   = each.value.disk_gb * 1024 * 1024 * 1024
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $src  = '${local.base_vhds[each.value.base]}'
      $dst  = '${var.vm_dir}\${upper(each.key)}\${upper(each.key)}.vhdx'
      $size = ${each.value.disk_gb * 1024 * 1024 * 1024}
      $dir  = Split-Path $dst
      if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
      if (-not (Test-Path $dst)) { Copy-Item $src $dst }
      if ((Get-VHD $dst).Size -lt $size) { Resize-VHD -Path $dst -SizeBytes $size }
    EOT
  }
}

# VM instances
resource "hyperv_machine_instance" "vm" {
  for_each = local.vms

  name       = upper(each.key)
  generation = 2

  processor_count      = each.value.cpu
  static_memory        = true
  memory_startup_bytes = each.value.ram_gb * 1024 * 1024 * 1024

  # Gen 2 security settings — disable Secure Boot for lab use
  vm_firmware {
    enable_secure_boot              = "Off"
    preferred_network_boot_protocol = "IPv4"
  }

  vm_processor {
    expose_virtualization_extensions = each.key == "vmm01" ? true : false
  }

  network_adaptors {
    name         = "LAN"
    switch_name  = var.switch_name
    wait_for_ips = false
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = "${var.vm_dir}\\${upper(each.key)}\\${upper(each.key)}.vhdx"
  }

  state                  = "Running"
  wait_for_state_timeout = 300
  wait_for_ips_timeout   = 0

  lifecycle {
    ignore_changes = [
      # Hyper-V sets a PXE+HDD boot order automatically; we don't manage it
      vm_firmware[0].boot_order,
    ]
  }

  depends_on = [null_resource.vm_disk]
}
