output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = local.subnet_ids
}

output "producer_security_group_id" {
  description = "Security group ID for producer cluster"
  value       = aws_security_group.producer.id
}

output "consumer_security_group_id" {
  description = "Security group ID for consumer workgroups"
  value       = aws_security_group.consumer.id
}

output "nlb_security_group_id" {
  description = "Security group ID for Network Load Balancer"
  value       = aws_security_group.nlb.id
}