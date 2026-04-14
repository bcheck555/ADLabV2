terraform {
  required_version = ">= 1.6.0"
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
  }
}

# The taliesins/hyperv provider connects to the Hyper-V host via WinRM.
# Since OpenTofu runs ON the Hyper-V host, we connect to localhost.
# This WinRM connection is host-to-host (loopback) and is unaffected by
# DISA GPOs applied to the lab VMs.
provider "hyperv" {
  host     = "127.0.0.1"
  port     = 5985
  user     = var.host_user
  password = var.host_password
  https    = false
  insecure = true
  use_ntlm = false
  timeout  = "30s"
}
