# vms.tf — All lab VMs defined as OpenTofu resources.
#
# Each VM gets a differencing VHDX cloned from its parent base image.
# Static IPs are NOT set here — Ansible sets them on first run.
# This keeps OpenTofu focused on VM lifecycle, Ansible on configuration.

locals {
  # Map ParentVHD type to base VHDX path
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

# Differencing VHDs — one per VM, cloned from the appropriate base image
resource "hyperv_vhd" "vm_disk" {
  for_each = local.vms

  path   = "${var.vm_dir}\\${upper(each.key)}\\${upper(each.key)}.vhdx"
  source = local.base_vhds[each.value.base]
  size   = each.value.disk_gb * 1024 * 1024 * 1024
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
    enable_secure_boot   = "Off"
    preferred_network_boot_protocol = "IPv4"
  }

  vm_processor {
    expose_virtualization_extensions = each.key == "vmm01" ? true : false
  }

  network_adaptors {
    name        = "LAN"
    switch_name = var.switch_name
    wait_for_ips = false
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.vm_disk[each.key].path
  }

  wait_for_state_timeout = 0   # Don't wait for running state — Ansible handles readiness
  wait_for_ips_timeout   = 0

  depends_on = [hyperv_vhd.vm_disk]
}
