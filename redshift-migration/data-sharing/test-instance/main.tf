# Standalone EC2 test instance deployment for NLB testing
# This runs separately from the main Redshift infrastructure

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# Import existing infrastructure data from data-sharing deployment
data "terraform_remote_state" "redshift" {
  backend = "s3"
  config = {
    bucket = "terraform-state-redshift-migration"
    key    = "redshift-data-sharing/dev/terraform.tfstate"
    region = "us-west-2"
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Generate SSH key pair
resource "tls_private_key" "test_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "test_key" {
  key_name   = "redshift-test-key-${random_id.key_suffix.hex}"
  public_key = tls_private_key.test_key.public_key_openssh
}

resource "random_id" "key_suffix" {
  byte_length = 4
}

# Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.test_key.private_key_pem
  filename        = "${path.module}/test-instance.pem"
  file_permission = "0600"
}

# Security group for test instance
resource "aws_security_group" "test_instance" {
  name_prefix = "redshift-test-instance-"
  description = "Security group for Redshift NLB test instance"
  vpc_id      = data.terraform_remote_state.redshift.outputs.vpc_id

  # SSH access from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "SSH from allowed IP"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name    = "redshift-test-instance-sg"
    Purpose = "nlb-testing"
  }
}

# EC2 instance for testing
resource "aws_instance" "test" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = data.terraform_remote_state.redshift.outputs.subnet_ids[0]
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
    
    echo "Test instance setup complete!" > /tmp/setup-complete
  EOF

  tags = {
    Name    = "redshift-nlb-test-instance"
    Purpose = "Testing NLB connectivity to Redshift"
  }

  # Wait for instance to be ready
  provisioner "local-exec" {
    command = "sleep 60"
  }

  # Copy test scripts to instance
  provisioner "file" {
    source      = "../test-nlb.sh"
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
    source      = "../test-nlb-connection.py"
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