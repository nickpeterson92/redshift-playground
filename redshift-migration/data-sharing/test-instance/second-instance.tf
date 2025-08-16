# Second EC2 test instance to verify load balancing

# EC2 instance 2 for testing
resource "aws_instance" "test2" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = data.terraform_remote_state.redshift.outputs.subnet_ids[1]  # Use different subnet
  key_name      = aws_key_pair.test_key.key_name
  
  vpc_security_group_ids = [aws_security_group.test_instance.id]
  
  associate_public_ip_address = true

  # User data to install PostgreSQL client and Python
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    
    # Install PostgreSQL client
    yum install -y postgresql15
    
    # Install Python and pip
    yum install -y python3 python3-pip
    
    # Install psycopg2
    pip3 install psycopg2-binary
    
    # Create test scripts directory
    mkdir -p /home/ec2-user/redshift-tests
    chown -R ec2-user:ec2-user /home/ec2-user/redshift-tests
    
    echo "Test instance 2 setup complete!" > /tmp/setup-complete
  EOF

  tags = {
    Name    = "redshift-nlb-test-instance-2"
    Purpose = "Testing NLB load distribution"
  }

  # Wait for instance to be ready
  provisioner "local-exec" {
    command = "sleep 60"
  }

  # Copy test scripts to instance
  provisioner "file" {
    source      = "../scripts/testing/test-nlb.sh"
    destination = "/home/ec2-user/redshift-tests/test-nlb.sh"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.test_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  provisioner "file" {
    source      = "../scripts/testing/test-nlb-connection.py"
    destination = "/home/ec2-user/redshift-tests/test-nlb-connection.py"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.test_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }

  # Make scripts executable
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ec2-user/redshift-tests/*.sh",
      "chmod +x /home/ec2-user/redshift-tests/*.py"
    ]
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.test_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }
  }
}

output "instance2_public_ip" {
  description = "Public IP of the second test instance"
  value       = aws_instance.test2.public_ip
}

output "test_both_instances" {
  description = "Commands to test from both instances simultaneously"
  value = <<-EOT
    # Terminal 1 - Test from Instance 1:
    ssh -i test-instance.pem ec2-user@${aws_instance.test.public_ip} \
      "cd redshift-tests && REDSHIFT_PASSWORD='Password123' python3 test-nlb-connection.py"
    
    # Terminal 2 - Test from Instance 2:
    ssh -i test-instance.pem ec2-user@${aws_instance.test2.public_ip} \
      "cd redshift-tests && REDSHIFT_PASSWORD='Password123' python3 test-nlb-connection.py"
  EOT
}