# Dynamic EC2 test instances for stress testing

# EC2 instances for testing
resource "aws_instance" "test" {
  count = var.instance_count
  
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnets.public.ids[count.index % length(data.aws_subnets.public.ids)]
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
    
    # Install psycopg2 and required packages for stress testing
    pip3 install psycopg2-binary numpy
    
    # Create test scripts directory
    mkdir -p /home/ec2-user/redshift-tests
    chown -R ec2-user:ec2-user /home/ec2-user/redshift-tests
    
    # Create instance identifier
    echo "${count.index + 1}" > /home/ec2-user/instance-id
    
    echo "Test instance ${count.index + 1} setup complete!" > /tmp/setup-complete
  EOF

  tags = {
    Name    = "redshift-nlb-test-instance-${count.index + 1}"
    Purpose = "Stress testing NLB load distribution"
    Index   = count.index + 1
  }
  
  # Note: Provisioners removed - test scripts run from local machine
  # To test from instances, SSH in and run scripts manually
}

# Outputs are defined in outputs.tf