# network.tf - references the existing LabNAT switch created by ad-hyperv-lab.
# The switch is NOT managed by OpenTofu (it pre-exists and is shared).
# Run the ad-hyperv-lab Ansible playbook first to create the switch and NAT.

data "hyperv_network_switch" "lab" {
  name = var.switch_name
}
