# Add a third subnet for Redshift Serverless requirements

# Get the existing VPC
data "aws_vpc" "redshift_vpc" {
  tags = {
    Name = "redshift-vpc"
  }
}

# Check available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create third subnet in a different AZ
resource "aws_subnet" "redshift_subnet_3" {
  vpc_id                  = data.aws_vpc.redshift_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true

  tags = {
    Name = "redshift-subnet-3"
  }
}

# Get the existing route table
data "aws_route_table" "redshift_rt" {
  vpc_id = data.aws_vpc.redshift_vpc.id
  
  filter {
    name   = "tag:Name"
    values = ["redshift-route-table"]
  }
}

# Associate the new subnet with the route table
resource "aws_route_table_association" "subnet_3_association" {
  subnet_id      = aws_subnet.redshift_subnet_3.id
  route_table_id = data.aws_route_table.redshift_rt.id
}

# Update the data source to include all subnets
data "aws_subnets" "all_redshift_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.redshift_vpc.id]
  }
  
  depends_on = [aws_subnet.redshift_subnet_3]
}