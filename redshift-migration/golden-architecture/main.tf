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
  
  tags = local.common_tags
  
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
  
  tags = local.common_tags
  
  depends_on = [module.consumers]
}

# Snapshot Restoration
# This module restores a snapshot to the producer namespace after deployment
module "snapshot_restore" {
  source = "./modules/snapshot-restore"
  
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
  
  # Snapshot restoration settings (if configured)
  restore_from_snapshot = var.restore_from_snapshot
  snapshot_identifier   = var.snapshot_identifier
  force_restore         = var.force_restore
  
  # Ensure snapshot restore runs after ALL infrastructure is ready
  depends_on = [
    module.producer,
    module.consumers,
    module.nlb
  ]
}