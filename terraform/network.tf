# network.tf — references the existing LabSwitch created by the host setup script.
# The switch is NOT managed by OpenTofu (it pre-exists and is shared).
# If LabSwitch doesn't exist yet, run provisioning/00-create-switch.ps1 first.

data "hyperv_network_switch" "lab" {
  name = var.switch_name
}
