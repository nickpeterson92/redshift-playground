output "namespace_id" {
  description = "Namespace ID for data sharing"
  value       = aws_redshiftserverless_namespace.consumer.namespace_id
}

output "namespace_name" {
  description = "Namespace name"
  value       = aws_redshiftserverless_namespace.consumer.namespace_name
}

output "workgroup_name" {
  description = "Workgroup name"
  value       = aws_redshiftserverless_workgroup.consumer.workgroup_name
}

output "endpoint" {
  description = "Workgroup endpoint"
  value       = aws_redshiftserverless_workgroup.consumer.endpoint
}

output "port" {
  description = "Workgroup port"
  value       = aws_redshiftserverless_workgroup.consumer.port
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.consumer.arn
}