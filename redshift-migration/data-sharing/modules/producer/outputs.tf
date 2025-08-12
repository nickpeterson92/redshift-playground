output "namespace_id" {
  description = "ID of the namespace"
  value       = aws_redshiftserverless_namespace.producer.namespace_id
}

output "namespace_arn" {
  description = "ARN of the namespace"
  value       = aws_redshiftserverless_namespace.producer.arn
}

output "workgroup_id" {
  description = "ID of the workgroup"
  value       = aws_redshiftserverless_workgroup.producer.workgroup_id
}

output "endpoint" {
  description = "Endpoint of the workgroup"
  value       = aws_redshiftserverless_workgroup.producer.endpoint
}

output "port" {
  description = "Port of the workgroup"
  value       = aws_redshiftserverless_workgroup.producer.port
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.producer.arn
}