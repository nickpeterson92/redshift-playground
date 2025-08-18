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

# Get public subnets from the VPC for test instances
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.redshift.outputs.vpc_id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["Public"]
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

# Note: EC2 instances are now defined in instances.tf with dynamic count