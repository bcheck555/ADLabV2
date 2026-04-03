output "vm_names" {
  description = "Names of all lab VMs"
  value       = [for vm in hyperv_machine_instance.vm : vm.name]
}

output "vm_state" {
  description = "Current state of each VM"
  value       = { for k, vm in hyperv_machine_instance.vm : k => vm.state }
}
