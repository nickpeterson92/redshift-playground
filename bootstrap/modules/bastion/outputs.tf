output "public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "instance_id" {
  description = "Instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "security_group_id" {
  description = "Security group ID of the bastion host"
  value       = aws_security_group.bastion.id
}