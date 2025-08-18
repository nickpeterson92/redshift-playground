output "delegate_cluster_arn" {
  description = "ARN of the ECS cluster running the delegate"
  value       = aws_ecs_cluster.harness_delegate.arn
}

output "delegate_service_name" {
  description = "Name of the ECS service running the delegate"
  value       = aws_ecs_service.harness_delegate.name
}

output "delegate_task_role_arn" {
  description = "ARN of the IAM role used by the delegate tasks"
  value       = aws_iam_role.ecs_task.arn
}

output "delegate_security_group_id" {
  description = "Security group ID of the delegate"
  value       = aws_security_group.harness_delegate.id
}

output "log_group_name" {
  description = "CloudWatch log group name for delegate logs"
  value       = aws_cloudwatch_log_group.harness_delegate.name
}