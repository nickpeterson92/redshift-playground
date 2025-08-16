# Outputs for Data Sharing Setup Module

output "setup_complete" {
  description = "Indicates that data sharing setup is complete"
  value       = null_resource.setup_datashare.id
}

output "consumer_states" {
  description = "Current state of consumer configurations"
  value       = { for k, v in null_resource.consumer_state : k => v.triggers }
}

output "setup_script_path" {
  description = "Path to the manual setup script"
  value       = local_file.setup_script.filename
}