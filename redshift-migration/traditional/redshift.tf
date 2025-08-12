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
  default     = "us-east-1"
}

variable "cluster_identifier" {
  description = "Unique identifier for the Redshift cluster"
  type        = string
  default     = "my-redshift-cluster"
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "mydb"
}

variable "master_username" {
  description = "Master username for the cluster"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password for the cluster"
  type        = string
  sensitive   = true
}

variable "allowed_ip" {
  description = "IP address allowed to connect to Redshift"
  type        = string
  default     = "71.231.5.129/32"  # Your current IP
}

# Create VPC for Redshift
resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "redshift_igw" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "redshift-igw"
  }
}

# Create subnets in different AZs (required for subnet group)
resource "aws_subnet" "redshift_subnet_1" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.0.0.0/23"  # 512 IPs for future serverless needs
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "redshift-subnet-1"
  }
}

resource "aws_subnet" "redshift_subnet_2" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.0.2.0/23"  # 512 IPs for future serverless needs
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "redshift-subnet-2"
  }
}

# Third subnet for Redshift Serverless (requires 3 AZs)
resource "aws_subnet" "redshift_subnet_3" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.0.4.0/23"  # 512 IPs for future serverless needs
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true

  tags = {
    Name = "redshift-subnet-3"
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create route table
resource "aws_route_table" "redshift_rt" {
  vpc_id = aws_vpc.redshift_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.redshift_igw.id
  }

  tags = {
    Name = "redshift-route-table"
  }
}

# Associate route table with subnets
resource "aws_route_table_association" "subnet_1_association" {
  subnet_id      = aws_subnet.redshift_subnet_1.id
  route_table_id = aws_route_table.redshift_rt.id
}

resource "aws_route_table_association" "subnet_2_association" {
  subnet_id      = aws_subnet.redshift_subnet_2.id
  route_table_id = aws_route_table.redshift_rt.id
}

resource "aws_route_table_association" "subnet_3_association" {
  subnet_id      = aws_subnet.redshift_subnet_3.id
  route_table_id = aws_route_table.redshift_rt.id
}

# Security group for Redshift
resource "aws_security_group" "redshift" {
  name_prefix = "redshift-sg-"
  description = "Security group for Redshift cluster"
  vpc_id      = aws_vpc.redshift_vpc.id

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
    Name = "redshift-security-group"
  }
}

# Subnet group for Redshift
resource "aws_redshift_subnet_group" "default" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = [aws_subnet.redshift_subnet_1.id, aws_subnet.redshift_subnet_2.id]

  tags = {
    Name = "Redshift subnet group"
  }
}

# Redshift cluster - most cost-effective configuration
resource "aws_redshift_cluster" "main" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password

  # Using ra3.xlplus - available in us-west-2 for single-node
  node_type       = "ra3.xlplus"
  cluster_type    = "single-node"
  number_of_nodes = 1

  # Cost optimization settings
  skip_final_snapshot                 = true
  automated_snapshot_retention_period = 1  # RA3 nodes require at least 1 day retention

  # Network configuration
  cluster_subnet_group_name = aws_redshift_subnet_group.default.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  # Make cluster publicly accessible for easy connection
  publicly_accessible = true

  # Encryption
  encrypted = false

  # Maintenance window
  preferred_maintenance_window = "sun:03:00-sun:04:00"

  tags = {
    Name        = var.cluster_identifier
    Environment = "development"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Redshift cluster endpoint"
  value       = aws_redshift_cluster.main.endpoint
}

output "cluster_port" {
  description = "Redshift cluster port"
  value       = aws_redshift_cluster.main.port
}

output "cluster_database_name" {
  description = "Name of the default database"
  value       = aws_redshift_cluster.main.database_name
}

output "jdbc_connection_string" {
  description = "JDBC connection string"
  value       = "jdbc:redshift://${aws_redshift_cluster.main.endpoint}/${aws_redshift_cluster.main.database_name}"
}

output "psql_connection_command" {
  description = "psql connection command"
  value       = "psql -h ${split(":", aws_redshift_cluster.main.endpoint)[0]} -p ${aws_redshift_cluster.main.port} -U ${var.master_username} -d ${var.database_name}"
}