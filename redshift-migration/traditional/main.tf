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

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Security group for Redshift clusters using bootstrap VPC
resource "aws_security_group" "redshift" {
  name_prefix = "redshift-clusters-sg-"
  description = "Security group for Redshift clusters"
  vpc_id      = data.terraform_remote_state.bootstrap.outputs.vpc_id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Allow access within VPC
    description = "Redshift port - VPC internal"
  }

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Redshift port - external access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "redshift-clusters-security-group"
    Environment = var.environment
  }
}

# Subnet group for Redshift using bootstrap PUBLIC subnets for publicly accessible clusters
resource "aws_redshift_subnet_group" "main" {
  name       = "${var.environment}-redshift-subnet-group"
  subnet_ids = data.terraform_remote_state.bootstrap.outputs.public_subnet_ids  # Changed to public subnets

  tags = {
    Name        = "${var.environment}-redshift-subnet-group"
    Environment = var.environment
  }
}

# IAM role for Redshift clusters
resource "aws_iam_role" "redshift" {
  name = "${var.environment}-redshift-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-redshift-cluster-role"
    Environment = var.environment
  }
}

# Attach S3 read policy to Redshift role
resource "aws_iam_role_policy_attachment" "redshift_s3_read" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.redshift.name
}

# Producer Redshift cluster (central data warehouse)
resource "aws_redshift_cluster" "producer" {
  cluster_identifier = "${var.environment}-producer-main"  # Changed name to avoid stuck cluster
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  # Using ra3.xlplus for cost optimization
  node_type       = var.node_type
  cluster_type    = var.cluster_type
  number_of_nodes = var.number_of_nodes

  # Cost optimization settings
  skip_final_snapshot                 = var.skip_final_snapshot
  automated_snapshot_retention_period = var.snapshot_retention_days

  # Network configuration
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  # Make cluster publicly accessible for easy connection
  publicly_accessible = var.publicly_accessible

  # Encryption
  encrypted = false  # Hardcoded to false to avoid modification conflicts

  # IAM role for S3 access
  iam_roles = [aws_iam_role.redshift.arn]

  # Maintenance window
  preferred_maintenance_window = var.maintenance_window

  # Logging configuration removed - use aws_redshift_logging resource instead if needed

  tags = {
    Name        = "${var.environment}-producer-cluster"
    Environment = var.environment
    Type        = "Producer"
    DataDomain  = "Central"
  }
}

# Consumer Redshift cluster 1 - Sales/Marketing domain
resource "aws_redshift_cluster" "consumer_sales" {
  cluster_identifier = "${var.environment}-consumer-sales-cluster"
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  # Using ra3.xlplus for cost optimization
  node_type       = var.consumer_node_type
  cluster_type    = var.consumer_cluster_type
  number_of_nodes = var.consumer_number_of_nodes

  # Cost optimization settings
  skip_final_snapshot                 = var.skip_final_snapshot
  automated_snapshot_retention_period = var.snapshot_retention_days

  # Network configuration
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  # Make cluster publicly accessible for easy connection
  publicly_accessible = var.publicly_accessible

  # Encryption
  encrypted = false  # Hardcoded to false to avoid modification conflicts

  # IAM role for S3 access
  iam_roles = [aws_iam_role.redshift.arn]

  # Maintenance window
  preferred_maintenance_window = var.maintenance_window

  # Logging configuration removed - use aws_redshift_logging resource instead if needed

  tags = {
    Name        = "${var.environment}-consumer-sales-cluster"
    Environment = var.environment
    Type        = "Consumer"
    DataDomain  = "Sales-Marketing"
  }
}

# Consumer Redshift cluster 2 - Operations/Analytics domain
resource "aws_redshift_cluster" "consumer_operations" {
  cluster_identifier = "${var.environment}-consumer-ops-cluster"
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  # Using ra3.xlplus for cost optimization
  node_type       = var.consumer_node_type
  cluster_type    = var.consumer_cluster_type
  number_of_nodes = var.consumer_number_of_nodes

  # Cost optimization settings
  skip_final_snapshot                 = var.skip_final_snapshot
  automated_snapshot_retention_period = var.snapshot_retention_days

  # Network configuration
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  # Make cluster publicly accessible for easy connection
  publicly_accessible = var.publicly_accessible

  # Encryption
  encrypted = false  # Hardcoded to false to avoid modification conflicts

  # IAM role for S3 access
  iam_roles = [aws_iam_role.redshift.arn]

  # Maintenance window
  preferred_maintenance_window = var.maintenance_window

  # Logging configuration removed - use aws_redshift_logging resource instead if needed

  tags = {
    Name        = "${var.environment}-consumer-ops-cluster"
    Environment = var.environment
    Type        = "Consumer"
    DataDomain  = "Operations-Analytics"
  }

  depends_on = [
    aws_redshift_subnet_group.main,
    aws_security_group.redshift
  ]
}

# Attach IAM roles to clusters
resource "aws_redshift_cluster_iam_roles" "producer" {
  cluster_identifier = aws_redshift_cluster.producer.cluster_identifier
  iam_role_arns      = [aws_iam_role.redshift.arn]
}

resource "aws_redshift_cluster_iam_roles" "consumer_sales" {
  cluster_identifier = aws_redshift_cluster.consumer_sales.cluster_identifier
  iam_role_arns      = [aws_iam_role.redshift.arn]
}

resource "aws_redshift_cluster_iam_roles" "consumer_operations" {
  cluster_identifier = aws_redshift_cluster.consumer_operations.cluster_identifier
  iam_role_arns      = [aws_iam_role.redshift.arn]
}