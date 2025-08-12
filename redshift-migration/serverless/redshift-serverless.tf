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

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "namespace_name" {
  description = "Name for the Redshift Serverless namespace"
  type        = string
  default     = "airline-serverless"
}

variable "workgroup_name" {
  description = "Name for the Redshift Serverless workgroup"
  type        = string
  default     = "airline-workgroup"
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "airline_dw"
}

variable "admin_username" {
  description = "Admin username for the namespace"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Admin password for the namespace"
  type        = string
  sensitive   = true
}

variable "allowed_ip" {
  description = "IP address allowed to connect to Redshift"
  type        = string
  default     = "71.231.5.129/32"
}

# Note: VPC and subnet data sources are defined in add-subnet.tf

# Security group for Redshift Serverless
resource "aws_security_group" "redshift_serverless" {
  name_prefix = "redshift-serverless-sg-"
  description = "Security group for Redshift Serverless"
  vpc_id      = data.aws_vpc.redshift_vpc.id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Redshift port - restricted to specific IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "redshift-serverless-security-group"
  }
}

# IAM role for Redshift Serverless
resource "aws_iam_role" "redshift_serverless" {
  name = "${var.namespace_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift-serverless.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for Redshift
resource "aws_iam_role_policy_attachment" "redshift_serverless_policy" {
  role       = aws_iam_role.redshift_serverless.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRedshiftAllCommandsFullAccess"
}

# S3 bucket for migration data
resource "aws_s3_bucket" "migration_bucket" {
  bucket = "redshift-migration-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name        = "Redshift Migration Bucket"
    Environment = "development"
  }
}

data "aws_caller_identity" "current" {}

# Redshift Serverless namespace
resource "aws_redshiftserverless_namespace" "airline" {
  namespace_name     = var.namespace_name
  db_name            = var.database_name
  admin_username     = var.admin_username
  admin_user_password = var.admin_password
  
  iam_roles = [aws_iam_role.redshift_serverless.arn]

  tags = {
    Name        = var.namespace_name
    Environment = "development"
  }
}

# Redshift Serverless workgroup
resource "aws_redshiftserverless_workgroup" "airline" {
  namespace_name = aws_redshiftserverless_namespace.airline.namespace_name
  workgroup_name = var.workgroup_name

  # Start with minimum capacity for cost optimization
  base_capacity = 32  # 32 RPUs (Redshift Processing Units)
  
  # Auto-scaling configuration
  max_capacity = 128  # Scale up to 128 RPUs under load
  
  # Network configuration
  subnet_ids         = data.aws_subnets.all_redshift_subnets.ids
  security_group_ids = [aws_security_group.redshift_serverless.id]
  
  publicly_accessible = true

  # Enhanced VPC routing for better performance
  enhanced_vpc_routing = true

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }

  tags = {
    Name        = var.workgroup_name
    Environment = "development"
  }
}

# Outputs
output "serverless_endpoint" {
  description = "Redshift Serverless endpoint"
  value       = aws_redshiftserverless_workgroup.airline.endpoint
}

output "serverless_port" {
  description = "Redshift Serverless port"
  value       = aws_redshiftserverless_workgroup.airline.port
}

output "serverless_database_name" {
  description = "Database name"
  value       = aws_redshiftserverless_namespace.airline.db_name
}

output "serverless_iam_role" {
  description = "IAM role for Redshift Serverless"
  value       = aws_iam_role.redshift_serverless.arn
}

output "jdbc_serverless_connection" {
  description = "JDBC connection string for serverless"
  value       = "jdbc:redshift://${aws_redshiftserverless_workgroup.airline.endpoint[0].address}:${aws_redshiftserverless_workgroup.airline.port}/${aws_redshiftserverless_namespace.airline.db_name}"
}

# Cost estimation outputs
output "estimated_monthly_cost" {
  description = "Estimated monthly cost (minimum)"
  value       = "Base: $0.36/RPU-hour * 32 RPUs = $11.52/hour when active (pay per use)"
}

output "cost_comparison" {
  description = "Cost comparison"
  value       = "Traditional ra3.xlplus: ~$414/month (24/7) vs Serverless: Pay only when running queries"
}