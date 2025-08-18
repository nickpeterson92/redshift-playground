# Networking module - manages VPC, subnets, and security groups

# Use existing VPC or create new one
data "aws_vpc" "existing" {
  count = var.create_vpc ? 0 : 1
  
  tags = merge(
    var.tags,
    {
      Name = var.vpc_name
    }
  )
}

resource "aws_vpc" "new" {
  count = var.create_vpc ? 1 : 0
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name        = var.vpc_name
      Environment = var.environment
    }
  )
}

locals {
  vpc_id = var.create_vpc ? aws_vpc.new[0].id : data.aws_vpc.existing[0].id
}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create subnets if needed
resource "aws_subnet" "redshift" {
  count = var.create_subnets ? length(var.subnet_cidrs) : 0
  
  vpc_id                  = local.vpc_id
  cidr_block              = var.subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.vpc_name}-subnet-${count.index + 1}"
      Environment = var.environment
      Type        = "Private"
    }
  )
}

# Get existing subnets if not creating - only private subnets
data "aws_subnets" "existing" {
  count = var.create_subnets ? 0 : 1
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  # Only get private subnets for Redshift and NLB
  filter {
    name   = "tag:Type"
    values = ["Private"]
  }
  
  # Optional: Filter by project if we're in a shared VPC
  # This ensures we only use subnets tagged for our project
  # Comment this out if using generic/shared subnets
  dynamic "filter" {
    for_each = lookup(var.tags, "Project", "") != "" ? [1] : []
    content {
      name   = "tag:Project"
      values = [var.tags["Project"]]
    }
  }
}

locals {
  subnet_ids = var.create_subnets ? aws_subnet.redshift[*].id : data.aws_subnets.existing[0].ids
}

# Internet Gateway (if creating VPC)
resource "aws_internet_gateway" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.new[0].id

  tags = {
    Name        = "${var.vpc_name}-igw"
    Environment = var.environment
  }
}

# Route table (if creating VPC)
resource "aws_route_table" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.new[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name        = "${var.vpc_name}-rt"
    Environment = var.environment
  }
}

# Route table associations
resource "aws_route_table_association" "subnet" {
  count = var.create_vpc ? length(aws_subnet.redshift) : 0
  
  subnet_id      = aws_subnet.redshift[count.index].id
  route_table_id = aws_route_table.main[0].id
}

# Security group for producer cluster
resource "aws_security_group" "producer" {
  name_prefix = "redshift-producer-"
  description = "Security group for Redshift producer cluster"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Redshift port - admin access"
  }
  
  # Allow access from consumer security group
  ingress {
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.consumer.id]
    description     = "Access from consumer workgroups"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "redshift-producer-sg"
      Environment = var.environment
      Purpose     = "producer-access"
    }
  )
}

# Security group for consumer workgroups
resource "aws_security_group" "consumer" {
  name_prefix = "redshift-consumer-"
  description = "Security group for Redshift consumer workgroups"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Redshift port - user access"
  }
  
  # Allow access from within VPC (for NLB health checks and connections)
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # VPC CIDR
    description = "Redshift port - VPC internal access (NLB)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "redshift-consumer-sg"
      Environment = var.environment
      Purpose     = "consumer-access"
    }
  )
}