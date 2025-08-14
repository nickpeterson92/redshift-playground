output "instance_public_ip" {
  description = "Public IP of the test instance"
  value       = aws_instance.test.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the test instance"
  value       = "ssh -i ${path.module}/test-instance.pem ec2-user@${aws_instance.test.public_ip}"
}

output "run_test_commands" {
  description = "Commands to run the test scripts"
  value = <<-EOT
    # SSH into the instance:
    ssh -i ${path.module}/test-instance.pem ec2-user@${aws_instance.test.public_ip}
    
    # Once connected, run tests:
    cd redshift-tests
    
    # Set your Redshift password:
    export REDSHIFT_PASSWORD='your-password-here'
    
    # Run the bash test:
    ./test-nlb.sh
    
    # Or run the Python test:
    python3 test-nlb-connection.py
  EOT
}

output "seamless_test_command" {
  description = "Run test seamlessly from your terminal"
  value = <<-EOT
    # Run bash test directly from your terminal:
    ssh -i ${path.module}/test-instance.pem ec2-user@${aws_instance.test.public_ip} "cd redshift-tests && REDSHIFT_PASSWORD='${var.redshift_password}' ./test-nlb.sh"
    
    # Run Python test directly from your terminal:
    ssh -i ${path.module}/test-instance.pem ec2-user@${aws_instance.test.public_ip} "cd redshift-tests && REDSHIFT_PASSWORD='${var.redshift_password}' python3 test-nlb-connection.py"
  EOT
  sensitive = true
}