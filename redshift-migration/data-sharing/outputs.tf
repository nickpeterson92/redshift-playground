output "producer_workgroup_id" {
  description = "ID of the producer workgroup"
  value       = module.producer.workgroup_id
}

output "producer_namespace_id" {
  description = "Namespace ID of the producer"
  value       = module.producer.namespace_id
}

output "producer_namespace_arn" {
  description = "ARN of the producer namespace"
  value       = module.producer.namespace_arn
}

output "producer_endpoint" {
  description = "Endpoint of the producer cluster"
  value       = module.producer.endpoint
  sensitive   = true
}

output "consumer_analytics_endpoint" {
  description = "Endpoint of the analytics consumer"
  value       = module.consumer_analytics.endpoint
  sensitive   = true
}

output "consumer_analytics_namespace_id" {
  description = "Namespace ID of the analytics consumer"
  value       = module.consumer_analytics.namespace_id
}

output "consumer_reporting_endpoint" {
  description = "Endpoint of the reporting consumer"
  value       = module.consumer_reporting.endpoint
  sensitive   = true
}

output "consumer_reporting_namespace_id" {
  description = "Namespace ID of the reporting consumer"
  value       = module.consumer_reporting.namespace_id
}

output "data_sharing_commands" {
  description = "Commands to set up data sharing"
  value = <<-EOT
    # Run on producer cluster:
    CREATE DATASHARE ${var.project_name}_share;
    ALTER DATASHARE ${var.project_name}_share ADD SCHEMA ${var.database_name};
    ALTER DATASHARE ${var.project_name}_share ADD ALL TABLES IN SCHEMA ${var.database_name};
    GRANT USAGE ON DATASHARE ${var.project_name}_share TO NAMESPACE '${module.consumer_analytics.namespace_id}';
    GRANT USAGE ON DATASHARE ${var.project_name}_share TO NAMESPACE '${module.consumer_reporting.namespace_id}';
    
    # Run on consumer clusters:
    CREATE DATABASE ${var.database_name}_shared FROM DATASHARE ${var.project_name}_share OF NAMESPACE '${module.producer.namespace_id}';
  EOT
}