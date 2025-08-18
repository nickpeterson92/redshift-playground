output "vpc_id" {
  description = "ID of the foundation VPC"
  value       = module.foundation_network.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.foundation_network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.foundation_network.public_subnet_ids
}

output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state (using existing)"
  value       = "terraform-state-redshift-migration"
}

output "terraform_locks_table" {
  description = "DynamoDB table for Terraform state locking (using existing)"
  value       = "terraform-state-locks"
}

output "backend_config_note" {
  description = "Backend configuration note"
  value       = "Using existing backend: s3://terraform-state-redshift-migration with DynamoDB table terraform-state-locks"
}

output "delegate_cluster_arn" {
  description = "ARN of the ECS cluster running Harness delegate"
  value       = module.harness_delegate.delegate_cluster_arn
}

output "delegate_task_role_arn" {
  description = "IAM role ARN used by the delegate"
  value       = module.harness_delegate.delegate_task_role_arn
}

output "delegate_log_group" {
  description = "CloudWatch log group for delegate logs"
  value       = module.harness_delegate.log_group_name
}

output "bastion_public_ip" {
  description = "Public IP of bastion host (if enabled)"
  value       = var.enable_bastion ? module.bastion[0].public_ip : null
}