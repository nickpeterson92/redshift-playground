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

# Common tags for all resources
locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Owner       = "DevOps"
      CostCenter  = "${var.project_name}-${var.environment}"
    },
    var.additional_tags
  )
}

# Common networking resources
module "networking" {
  source = "./modules/networking"
  
  vpc_name       = var.vpc_name
  environment    = var.environment
  allowed_ip     = var.allowed_ip
  create_vpc     = var.create_vpc
  vpc_cidr       = var.vpc_cidr
  create_subnets = var.create_subnets
  subnet_cidrs   = var.subnet_cidrs
  
  tags = local.common_tags
}

# Data source to read traditional deployment outputs (producer cluster)
data "terraform_remote_state" "traditional" {
  backend = "s3"
  config = {
    bucket = "terraform-state-redshift-migration"
    key    = "traditional/terraform.tfstate"
    region = var.aws_region
  }
}

# Note: Producer is now provided by the traditional deployment
# The traditional deployment manages the producer Redshift cluster
# Consumers will establish data sharing with the traditional producer

# Create multiple generic consumer instances
module "consumers" {
  source = "./modules/consumer"
  count  = var.consumer_count

  namespace_name = "${var.project_name}-consumer-${count.index + 1}"
  workgroup_name = "${var.project_name}-consumer-wg-${count.index + 1}"
  database_name  = "consumer_db"
  admin_username = var.master_username
  admin_password = var.master_password
  
  # All consumers have identical capacity for even load distribution
  base_capacity = var.consumer_base_capacity
  max_capacity  = var.consumer_max_capacity
  
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.subnet_ids
  security_group_id = module.networking.consumer_security_group_id
  
  environment    = var.environment
  consumer_index = count.index + 1
  aws_region     = var.aws_region
  
  tags = local.common_tags
  
  # Consumers can be created independently as producer is in traditional deployment
  # Data sharing will be established after both are ready
}

# Network Load Balancer to distribute queries across consumers
module "nlb" {
  source = "./modules/nlb"
  
  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.networking.vpc_id
  subnet_ids     = module.networking.subnet_ids
  consumer_count = var.consumer_count
  
  # Create endpoint list using stable VPC endpoint IPs for NLB
  # Use try() to handle cases where endpoints don't exist yet or during destroy
  consumer_endpoints = try(
    flatten([
      for idx, consumer in module.consumers : [
        for ip in try(consumer.vpc_endpoint_ips, []) : {
          address = ip
          port    = try(consumer.port, 5439)
        }
      ] if length(try(consumer.vpc_endpoint_ips, [])) > 0
    ]),
    []
  )
  
  tags = local.common_tags
  
  depends_on = [module.consumers]
}

# Note: Snapshot restoration removed since we're using existing producer from traditional deployment
# Data sharing will be configured manually between traditional producer and serverless consumers