output "instance_count" {
  description = "Number of test instances deployed"
  value       = var.instance_count
}

output "instance_public_ips" {
  description = "Public IPs of all test instances"
  value       = aws_instance.test[*].public_ip
}

output "instance_private_ips" {
  description = "Private IPs of all test instances"
  value       = aws_instance.test[*].private_ip
}

output "ssh_commands" {
  description = "SSH commands for all instances"
  value = {
    for idx, ip in aws_instance.test[*].public_ip :
    "instance_${idx + 1}" => "ssh -i ${path.module}/test-instance.pem ec2-user@${ip}"
  }
}

output "stress_test_info" {
  description = "Information for running stress tests"
  value = <<-EOT
    ============================================
    STRESS TEST DEPLOYMENT READY
    ============================================
    Instances Deployed: ${var.instance_count}
    
    To run a stress test:
    1. Use the stress-test.sh script
    2. Or run manually on each instance
    
    Quick test command:
    ./stress-test.sh
    
    To deploy more instances:
    terraform apply -var="instance_count=10"
  EOT
}