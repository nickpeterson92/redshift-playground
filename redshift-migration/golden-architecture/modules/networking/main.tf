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

# Get the actual CIDR blocks of the subnets we're using
data "aws_subnet" "actual" {
  count = length(local.subnet_ids)
  id    = local.subnet_ids[count.index]
}

locals {
  # Use actual subnet CIDRs for security group rules
  actual_subnet_cidrs = data.aws_subnet.actual[*].cidr_block
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

# Security group for NLB (Network Load Balancer)
# Controls who can send traffic TO the load balancer
resource "aws_security_group" "nlb" {
  name_prefix = "redshift-nlb-"
  description = "Security group for Redshift NLB - controls inbound traffic to load balancer"
  vpc_id      = local.vpc_id

  # Ingress: Allow traffic from clients to the NLB on Redshift port
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Redshift port - client access to NLB"
  }
  
  # Additional ingress for VPC-internal access if needed
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # VPC CIDR for internal clients
    description = "Redshift port - VPC internal access to NLB"
  }

  # Egress: Allow all outbound traffic (will be refined by target security groups)
  # The consumer security groups will control what the NLB can actually reach
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name        = "redshift-nlb-sg"
      Environment = var.environment
      Purpose     = "nlb-load-balancer"
    }
  )
}

# Security group for consumer workgroups (Redshift targets)
# Controls who can send traffic TO the Redshift consumer instances
resource "aws_security_group" "consumer" {
  name_prefix = "redshift-consumer-"
  description = "Security group for Redshift consumer workgroups - ensures traffic only from NLB"
  vpc_id      = local.vpc_id
  
  # Optional: Direct admin access for troubleshooting (can be removed in production)
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Direct admin access for troubleshooting (optional)"
  }
  
  # CRITICAL: Allow health checks from NLB subnet CIDRs
  # NLB health checks come from the NLB node IPs within the subnets
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = local.actual_subnet_cidrs
    description = "NLB health checks from subnet CIDRs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name        = "redshift-consumer-sg"
      Environment = var.environment
      Purpose     = "consumer-targets"
    }
  )
}

# Add ingress rules to consumer SG from NLB SG (for client traffic through NLB)
# This allows actual client traffic that flows through the NLB
resource "aws_security_group_rule" "consumer_from_nlb" {
  type                     = "ingress"
  from_port                = 5439
  to_port                  = 5439
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb.id
  security_group_id        = aws_security_group.consumer.id
  description              = "Client traffic routed through NLB"
}