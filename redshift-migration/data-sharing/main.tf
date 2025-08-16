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
}

# Producer namespace for writes (serverless)
module "producer" {
  source = "./modules/producer"
  
  namespace_name  = "${var.project_name}-producer"
  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password
  base_capacity   = var.producer_base_capacity
  max_capacity    = var.producer_max_capacity
  
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.subnet_ids
  security_group_id = module.networking.producer_security_group_id
  
  environment = var.environment
  project     = var.project_name
}

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
  
  # CRITICAL: Consumers must wait for producer to be created first
  # This ensures data sharing can be established properly
  depends_on = [module.producer]
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
  
  depends_on = [module.consumers]
}

# Automated Data Sharing Setup
# This module automatically configures data sharing between producer and consumers
# It intelligently detects new consumers and only configures those that need setup
module "datashare_setup" {
  source = "./modules/datashare-setup"
  
  environment           = var.environment
  producer_endpoint     = try(module.producer.endpoint[0].address, "")
  producer_namespace_id = module.producer.namespace_id
  
  # Create consumer configuration map
  consumer_configs = {
    for idx, consumer in module.consumers : 
    "consumer-${idx}" => {
      namespace_id = consumer.namespace_id
      endpoint     = try(consumer.endpoint[0].address, "")
    }
  }
  
  master_username = var.master_username
  master_password = var.master_password
  database_name   = var.database_name
  aws_region      = var.aws_region
  
  # Ensure setup runs after all infrastructure is ready
  depends_on = [
    module.producer,
    module.consumers,
    module.nlb
  ]
}