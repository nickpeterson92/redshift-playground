terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# Data source to read bootstrap outputs
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = "terraform-state-redshift-migration"
    key    = "bootstrap/terraform.tfstate"
    region = var.aws_region
  }
}

# Data source to read traditional deployment outputs
data "terraform_remote_state" "traditional" {
  backend = "s3"
  config = {
    bucket = "terraform-state-redshift-migration"
    key    = "traditional/terraform.tfstate"
    region = var.aws_region
  }
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Security group for Test Drive EC2 instance
resource "aws_security_group" "test_drive" {
  name_prefix = "${var.environment}-test-drive-sg-"
  description = "Security group for Redshift Test Drive EC2 instance"
  vpc_id      = data.terraform_remote_state.bootstrap.outputs.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-test-drive-security-group"
    Environment = var.environment
    Purpose     = "Redshift Test Drive"
  }
}

# IAM role for Test Drive EC2 instance
resource "aws_iam_role" "test_drive_ec2" {
  name = "${var.environment}-test-drive-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-test-drive-ec2-role"
    Environment = var.environment
  }
}

# IAM policy for Test Drive operations
resource "aws_iam_role_policy" "test_drive" {
  name = "${var.environment}-test-drive-policy"
  role = aws_iam_role.test_drive_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.test_drive_workload.arn,
          "${aws_s3_bucket.test_drive_workload.arn}/*",
          data.terraform_remote_state.traditional.outputs.redshift_logs_s3_bucket_arn,
          "${data.terraform_remote_state.traditional.outputs.redshift_logs_s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "redshift:DescribeClusters",
          "redshift:GetClusterCredentials",
          "redshift:DescribeLoggingStatus",
          "redshift-data:ExecuteStatement",
          "redshift-data:GetStatementResult",
          "redshift-data:DescribeStatement",
          "redshift-data:ListStatements"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/test-drive/*"
      }
    ]
  })
}

# IAM instance profile for EC2
resource "aws_iam_instance_profile" "test_drive" {
  name = "${var.environment}-test-drive-profile"
  role = aws_iam_role.test_drive_ec2.name
}

# S3 bucket for Test Drive workload storage
resource "aws_s3_bucket" "test_drive_workload" {
  bucket        = "${var.environment}-test-drive-workload-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.environment}-test-drive-workload"
    Environment = var.environment
    Purpose     = "Redshift Test Drive workload storage"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "test_drive_workload" {
  bucket = aws_s3_bucket.test_drive_workload.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "test_drive_workload" {
  bucket = aws_s3_bucket.test_drive_workload.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Generate SSH key pair for Test Drive access
resource "tls_private_key" "test_drive_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "test_drive_key" {
  key_name   = "${var.environment}-test-drive-key"
  public_key = tls_private_key.test_drive_key.public_key_openssh
}

# Save private key locally
resource "local_file" "test_drive_private_key" {
  content  = tls_private_key.test_drive_key.private_key_pem
  filename = "${path.module}/test-drive-key.pem"
  file_permission = "0600"
}

# EC2 instance for Redshift Test Drive
resource "aws_instance" "test_drive" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.test_drive_instance_type
  subnet_id     = data.terraform_remote_state.bootstrap.outputs.public_subnet_ids[0]
  key_name      = aws_key_pair.test_drive_key.key_name
  
  vpc_security_group_ids = [aws_security_group.test_drive.id]
  # IAM instance profile required for S3 access to audit logs and workload storage
  iam_instance_profile   = aws_iam_instance_profile.test_drive.name
  
  associate_public_ip_address = true
  
  # Root block device for Test Drive storage (32GB as per requirements)
  root_block_device {
    volume_type = "gp3"
    volume_size = 32
    # Encryption removed to avoid SCP issues - add back if needed with proper KMS key
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    aws_region                = var.aws_region
    environment               = var.environment
    workload_bucket           = aws_s3_bucket.test_drive_workload.id
    audit_logs_bucket         = data.terraform_remote_state.traditional.outputs.redshift_logs_s3_bucket
    producer_endpoint         = data.terraform_remote_state.traditional.outputs.producer_cluster_endpoint
    consumer_sales_endpoint   = data.terraform_remote_state.traditional.outputs.consumer_sales_cluster_endpoint
    consumer_ops_endpoint     = data.terraform_remote_state.traditional.outputs.consumer_operations_cluster_endpoint
    redshift_database         = var.database_name
    redshift_user             = var.master_username
    redshift_password         = var.master_password
  }))

  tags = {
    Name        = "${var.environment}-test-drive-instance"
    Environment = var.environment
    Purpose     = "Redshift Test Drive"
    Type        = "m5.8xlarge recommended for production"
  }
}

# CloudWatch Log Group for Test Drive
resource "aws_cloudwatch_log_group" "test_drive" {
  name              = "/aws/test-drive/${var.environment}"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-test-drive-logs"
    Environment = var.environment
  }
}