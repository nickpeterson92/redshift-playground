# Infrastructure outputs for test instance
output "vpc_id" {
  description = "VPC ID for test instance deployment"
  value       = module.networking.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs for test instance deployment"
  value       = module.networking.subnet_ids
}

output "producer_cluster_id" {
  description = "Producer cluster ID from traditional deployment"
  value       = data.terraform_remote_state.traditional.outputs.producer_cluster_id
}

output "producer_endpoint" {
  description = "Producer cluster endpoint from traditional deployment"
  value       = data.terraform_remote_state.traditional.outputs.producer_cluster_endpoint
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

output "security_group_info" {
  description = "Security group configuration for NLB and targets"
  value = {
    nlb_security_group_id      = module.networking.nlb_security_group_id
    consumer_security_group_id = module.networking.consumer_security_group_id
    producer_security_group_id = module.networking.producer_security_group_id
    note = "NLB SG controls access to load balancer. Consumer SG only allows traffic from NLB SG, ensuring all traffic flows through the NLB."
  }
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


output "master_username" {
  description = "Master username for database access"
  value       = var.master_username
  sensitive   = true
}

output "master_password" {
  description = "Master password for database access"
  value       = var.master_password
  sensitive   = true
}

output "database_name" {
  description = "Database name"
  value       = var.database_name
}

output "data_sharing_commands" {
  description = "Commands to set up data sharing after deployment"
  value = <<-EOT
    ################################################
    # DATA SHARING SETUP - RUN ON TRADITIONAL PRODUCER CLUSTER
    ################################################
    
    # 1. First, get the producer namespace ID:
    SELECT current_namespace;
    
    # 2. Create SHARED AIRLINE CORE DATA share (shared with all consumers):
    CREATE DATASHARE airline_core_share SET PUBLICACCESSIBLE TRUE;
    ALTER DATASHARE airline_core_share ADD SCHEMA shared_airline;
    ALTER DATASHARE airline_core_share ADD ALL TABLES IN SCHEMA shared_airline;
    
    # 3. Create SALES DOMAIN DATA share (for sales analytics):
    CREATE DATASHARE sales_data_share SET PUBLICACCESSIBLE TRUE;
    ALTER DATASHARE sales_data_share ADD SCHEMA sales_domain;
    ALTER DATASHARE sales_data_share ADD ALL TABLES IN SCHEMA sales_domain;
    
    # 4. Create OPERATIONS DOMAIN DATA share (for operations analytics):
    CREATE DATASHARE operations_data_share SET PUBLICACCESSIBLE TRUE;
    ALTER DATASHARE operations_data_share ADD SCHEMA operations_domain;
    ALTER DATASHARE operations_data_share ADD ALL TABLES IN SCHEMA operations_domain;
    
    # 5. Grant ALL shares to EACH golden architecture consumer:
    ${join("\n    ", [for id in module.consumers[*].namespace_id : 
      "-- Consumer namespace: ${id}\n    GRANT USAGE ON DATASHARE airline_core_share TO NAMESPACE '${id}';\n    GRANT USAGE ON DATASHARE sales_data_share TO NAMESPACE '${id}';\n    GRANT USAGE ON DATASHARE operations_data_share TO NAMESPACE '${id}';"
    ])}
    
    ################################################
    # ON EACH GOLDEN ARCHITECTURE CONSUMER - Create databases from shares
    ################################################
    # (Connect to each consumer individually)
    # Replace <PRODUCER_NAMESPACE_ID> with the actual producer namespace ID from step 1
    
    -- Create database for shared airline core data
    CREATE DATABASE airline_shared FROM DATASHARE airline_core_share 
        OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';
    
    -- Create database for sales domain data
    CREATE DATABASE sales_analytics FROM DATASHARE sales_data_share 
        OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';
    
    -- Create database for operations domain data  
    CREATE DATABASE operations_analytics FROM DATASHARE operations_data_share 
        OF NAMESPACE '<PRODUCER_NAMESPACE_ID>';
    
    ################################################
    # VERIFICATION QUERIES - Run on each consumer
    ################################################
    
    -- Verify shared airline data:
    SELECT COUNT(*) FROM airline_shared.shared_airline.airports;
    SELECT COUNT(*) FROM airline_shared.shared_airline.aircraft;
    SELECT COUNT(*) FROM airline_shared.shared_airline.flights;
    SELECT COUNT(*) FROM airline_shared.shared_airline.routes;
    
    -- Verify sales domain data:
    SELECT COUNT(*) FROM sales_analytics.sales_domain.customers;
    SELECT COUNT(*) FROM sales_analytics.sales_domain.bookings;
    SELECT COUNT(*) FROM sales_analytics.sales_domain.marketing_campaigns;
    SELECT COUNT(*) FROM sales_analytics.sales_domain.daily_revenue;
    
    -- Verify operations domain data:
    SELECT COUNT(*) FROM operations_analytics.operations_domain.maintenance_logs;
    SELECT COUNT(*) FROM operations_analytics.operations_domain.crew_assignments;
    SELECT COUNT(*) FROM operations_analytics.operations_domain.daily_operations_metrics;
    SELECT COUNT(*) FROM operations_analytics.operations_domain.ground_handling;
    
    -- Example analytical queries:
    -- Flight performance across domains
    SELECT * FROM airline_shared.shared_airline.flight_performance LIMIT 10;
    
    -- Customer 360 view
    SELECT * FROM sales_analytics.sales_domain.customer_360 LIMIT 10;
    
    -- Fleet status
    SELECT * FROM operations_analytics.operations_domain.fleet_status LIMIT 10;
  EOT
}