# Infrastructure outputs for test instance
output "vpc_id" {
  description = "VPC ID for test instance deployment"
  value       = module.networking.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs for test instance deployment"
  value       = module.networking.subnet_ids
}

output "producer_namespace_id" {
  description = "Producer namespace ID for data sharing setup"
  value       = module.producer.namespace_id
}

output "producer_endpoint" {
  description = "Producer workgroup endpoint"
  value       = module.producer.endpoint
}

output "consumer_namespace_ids" {
  description = "List of consumer namespace IDs"
  value       = [for c in module.consumers : c.namespace_id]
}

output "consumer_endpoints" {
  description = "Direct consumer endpoints (for testing individual consumers)"
  value = {
    for idx, consumer in module.consumers : 
    "consumer-${idx + 1}" => consumer.endpoint
  }
}

output "nlb_endpoint" {
  description = "NLB endpoint for distributed query access"
  value       = module.nlb.nlb_dns_name
}

output "nlb_connection_string" {
  description = "JDBC connection string via NLB"
  value       = "jdbc:redshift://${module.nlb.nlb_dns_name}:5439/${var.database_name}"
}

output "connection_info" {
  description = "Connection information for clients"
  sensitive   = true
  value = {
    nlb_endpoint = module.nlb.nlb_dns_name
    port         = 5439
    database     = var.database_name
    username     = var.master_username
    note         = "Use the NLB endpoint for automatic load distribution across ${var.consumer_count} consumers"
  }
}

output "data_sharing_commands" {
  description = "Commands to set up data sharing after deployment"
  value = <<-EOT
    # Connect to producer and run:
    CREATE DATASHARE airline_share SET PUBLICACCESSIBLE TRUE;
    ALTER DATASHARE airline_share ADD SCHEMA airline_dw;
    ALTER DATASHARE airline_share ADD ALL TABLES IN SCHEMA airline_dw;
    
    # Grant to each consumer (run for each consumer namespace ID):
    ${join("\n    ", [for id in module.consumers[*].namespace_id : "GRANT USAGE ON DATASHARE airline_share TO NAMESPACE '${id}';"])}
    
    # On each consumer, create database from share:
    # (Connect to each consumer individually)
    CREATE DATABASE airline_shared FROM DATASHARE airline_share OF NAMESPACE '${module.producer.namespace_id}';
    
    # Verify the share is working:
    SELECT * FROM airline_shared.airline_dw.dim_aircraft LIMIT 10;
    SELECT * FROM airline_shared.airline_dw.dim_airport LIMIT 10;
    SELECT * FROM airline_shared.airline_dw.fact_bookings LIMIT 10;
  EOT
}

output "scaling_instructions" {
  description = "How to scale the consumer fleet"
  value = <<-EOT
    To add more consumers:
    1. Update consumer_count variable (current: ${var.consumer_count})
    2. Run: terraform apply
    3. New consumers automatically added to NLB target group
    
    To adjust consumer capacity:
    1. Modify local.consumer_base_capacity and local.consumer_max_capacity in main.tf
    2. Run: terraform apply
    
    The NLB automatically distributes queries across all healthy consumers.
  EOT
}