# Producer Cluster Outputs
output "producer_cluster_id" {
  description = "Producer cluster identifier"
  value       = aws_redshift_cluster.producer.id
}

output "producer_cluster_endpoint" {
  description = "Producer cluster endpoint"
  value       = aws_redshift_cluster.producer.endpoint
}

output "producer_cluster_port" {
  description = "Producer cluster port"
  value       = aws_redshift_cluster.producer.port
}

output "producer_cluster_database_name" {
  description = "Name of the producer database"
  value       = aws_redshift_cluster.producer.database_name
}

output "producer_jdbc_connection" {
  description = "Producer JDBC connection string"
  value       = "jdbc:redshift://${aws_redshift_cluster.producer.endpoint}/${aws_redshift_cluster.producer.database_name}"
}

output "producer_psql_command" {
  description = "Producer psql connection command"
  value       = "psql -h ${split(":", aws_redshift_cluster.producer.endpoint)[0]} -p ${aws_redshift_cluster.producer.port} -U ${var.master_username} -d ${var.database_name}"
}

# Consumer Sales Cluster Outputs
output "consumer_sales_cluster_id" {
  description = "Consumer Sales cluster identifier"
  value       = aws_redshift_cluster.consumer_sales.id
}

output "consumer_sales_cluster_endpoint" {
  description = "Consumer Sales cluster endpoint"
  value       = aws_redshift_cluster.consumer_sales.endpoint
}

output "consumer_sales_cluster_port" {
  description = "Consumer Sales cluster port"
  value       = aws_redshift_cluster.consumer_sales.port
}

output "consumer_sales_jdbc_connection" {
  description = "Consumer Sales JDBC connection string"
  value       = "jdbc:redshift://${aws_redshift_cluster.consumer_sales.endpoint}/${aws_redshift_cluster.consumer_sales.database_name}"
}

output "consumer_sales_psql_command" {
  description = "Consumer Sales psql connection command"
  value       = "psql -h ${split(":", aws_redshift_cluster.consumer_sales.endpoint)[0]} -p ${aws_redshift_cluster.consumer_sales.port} -U ${var.master_username} -d ${var.database_name}"
}

# Consumer Operations Cluster Outputs
output "consumer_operations_cluster_id" {
  description = "Consumer Operations cluster identifier"
  value       = aws_redshift_cluster.consumer_operations.id
}

output "consumer_operations_cluster_endpoint" {
  description = "Consumer Operations cluster endpoint"
  value       = aws_redshift_cluster.consumer_operations.endpoint
}

output "consumer_operations_cluster_port" {
  description = "Consumer Operations cluster port"
  value       = aws_redshift_cluster.consumer_operations.port
}

output "consumer_operations_jdbc_connection" {
  description = "Consumer Operations JDBC connection string"
  value       = "jdbc:redshift://${aws_redshift_cluster.consumer_operations.endpoint}/${aws_redshift_cluster.consumer_operations.database_name}"
}

output "consumer_operations_psql_command" {
  description = "Consumer Operations psql connection command"
  value       = "psql -h ${split(":", aws_redshift_cluster.consumer_operations.endpoint)[0]} -p ${aws_redshift_cluster.consumer_operations.port} -U ${var.master_username} -d ${var.database_name}"
}

# Security Group Output
output "redshift_security_group_id" {
  description = "ID of the Redshift security group"
  value       = aws_security_group.redshift.id
}

# Subnet Group Output
output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group"
  value       = aws_redshift_subnet_group.main.name
}

# IAM Role Output
output "redshift_iam_role_arn" {
  description = "ARN of the Redshift IAM role"
  value       = aws_iam_role.redshift.arn
}

# Logging Outputs
output "redshift_logs_s3_bucket" {
  description = "S3 bucket name for Redshift audit logs"
  value       = aws_s3_bucket.redshift_logs.id
}

output "redshift_logs_s3_bucket_arn" {
  description = "S3 bucket ARN for Redshift audit logs"
  value       = aws_s3_bucket.redshift_logs.arn
}

output "audit_logging_enabled" {
  description = "Status of audit logging for consumer clusters"
  value = {
    consumer_sales      = "Enabled - Logs at s3://${aws_s3_bucket.redshift_logs.id}/consumer-sales/"
    consumer_operations = "Enabled - Logs at s3://${aws_s3_bucket.redshift_logs.id}/consumer-operations/"
  }
}

# VPC Information (from bootstrap)
output "vpc_id" {
  description = "VPC ID from bootstrap"
  value       = data.terraform_remote_state.bootstrap.outputs.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs from bootstrap"
  value       = data.terraform_remote_state.bootstrap.outputs.private_subnet_ids
}

# Data Sharing Setup Instructions
output "data_sharing_setup" {
  description = "Instructions for setting up data sharing between clusters"
  value = <<-EOT
    To set up data sharing between clusters:
    
    1. Get namespace IDs by connecting to each cluster and running:
       SELECT current_namespace;
    
    2. On the Producer cluster, create a datashare:
       -- Connect to producer cluster
       CREATE DATASHARE sales_share;
       ALTER DATASHARE sales_share ADD SCHEMA sales_schema;
       ALTER DATASHARE sales_share ADD ALL TABLES IN SCHEMA sales_schema;
       
       -- Grant to consumer (replace NAMESPACE_ID with actual value from step 1)
       GRANT USAGE ON DATASHARE sales_share TO NAMESPACE 'CONSUMER_NAMESPACE_ID';
    
    3. On the Consumer cluster, create database from datashare:
       -- Connect to consumer cluster (replace PRODUCER_NAMESPACE_ID with actual value)
       CREATE DATABASE sales_db FROM DATASHARE sales_share OF NAMESPACE 'PRODUCER_NAMESPACE_ID';
    
    4. Verify the share is working:
       SELECT * FROM sales_db.sales_schema.your_table LIMIT 10;
    
    Note: The cluster_namespace_identifier attribute requires AWS provider version 5.31+
    If using an older version, query namespace IDs using SQL as shown above.
  EOT
}