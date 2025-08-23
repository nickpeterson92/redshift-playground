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

output "endpoint_address" {
  description = "Workgroup endpoint address (without port)"
  value       = try(aws_redshiftserverless_workgroup.consumer.endpoint[0].address, "")
}

output "vpc_endpoint_name" {
  description = "Name of the VPC endpoint for lookup"
  value = aws_redshiftserverless_endpoint_access.consumer.endpoint_name
}

output "vpc_endpoint_ips" {
  description = "VPC endpoint IPs are discovered dynamically by NLB script"
  value = []  # No longer needed - NLB script discovers IPs directly
}


output "port" {
  description = "Workgroup port"
  value       = aws_redshiftserverless_workgroup.consumer.port
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.consumer.arn
}

output "ready" {
  description = "Indicates workgroup is ready (used for dependencies)"
  value       = aws_redshiftserverless_workgroup.consumer.id
}