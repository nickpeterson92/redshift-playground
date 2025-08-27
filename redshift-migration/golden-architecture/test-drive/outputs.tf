# EC2 Instance Information
output "test_drive_instance_id" {
  description = "ID of the Test Drive EC2 instance"
  value       = aws_instance.test_drive.id
}

output "test_drive_instance_public_ip" {
  description = "Public IP address of Test Drive instance"
  value       = aws_instance.test_drive.public_ip
}

output "test_drive_instance_public_dns" {
  description = "Public DNS of Test Drive instance"
  value       = aws_instance.test_drive.public_dns
}

# S3 Bucket Information
output "test_drive_workload_bucket" {
  description = "S3 bucket for Test Drive workload storage"
  value       = aws_s3_bucket.test_drive_workload.id
}

output "test_drive_workload_bucket_arn" {
  description = "ARN of Test Drive workload bucket"
  value       = aws_s3_bucket.test_drive_workload.arn
}

# IAM Role Information
output "test_drive_role_arn" {
  description = "ARN of Test Drive IAM role"
  value       = aws_iam_role.test_drive_ec2.arn
}

# SSH Connection Command
output "ssh_connection_command" {
  description = "SSH command to connect to Test Drive instance"
  value       = "ssh -i ${path.module}/test-drive-key.pem ec2-user@${aws_instance.test_drive.public_ip}"
}

# Test Drive Commands
output "test_drive_commands" {
  description = "Commands to run Test Drive operations"
  value = {
    switch_user      = "sudo su - testdrive"
    extract_workload = "/opt/redshift-test-drive/extract-workload.sh"
    replay_sales     = "/opt/redshift-test-drive/replay-workload.sh sales"
    replay_ops       = "/opt/redshift-test-drive/replay-workload.sh ops"
  }
}

# Configuration Paths
output "configuration_paths" {
  description = "Paths to Test Drive configuration files"
  value = {
    extract_config      = "/opt/redshift-test-drive/config/extract.yaml"
    replay_sales_config = "/opt/redshift-test-drive/config/replay-sales.yaml"
    replay_ops_config   = "/opt/redshift-test-drive/config/replay-ops.yaml"
  }
}