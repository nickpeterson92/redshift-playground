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

# Foundation VPC that will persist across all deployments
module "foundation_network" {
  source = "./modules/networking"
  
  vpc_cidr             = var.vpc_cidr
  environment          = var.environment
  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = local.common_tags
}

# COMMENTED OUT - Using existing backend from golden-architecture deployment
# module "terraform_backend" {
#   source = "./modules/backend"
#   
#   bucket_name = "${var.organization}-${var.environment}-terraform-state"
#   environment = var.environment
#   
#   tags = local.common_tags
# }

# Harness Delegate running on ECS Fargate
module "harness_delegate" {
  source = "./modules/harness-delegate"
  
  delegate_name       = "${var.organization}-${var.environment}-delegate"
  harness_account_id  = var.harness_account_id
  delegate_token      = var.harness_delegate_token
  delegate_image      = var.delegate_image
  
  # Network configuration
  vpc_id              = module.foundation_network.vpc_id
  private_subnet_ids  = module.foundation_network.private_subnet_ids
  
  # Delegate sizing
  cpu                 = var.delegate_cpu
  memory              = var.delegate_memory
  replicas            = var.delegate_replicas
  
  # Permissions - what this delegate can manage
  managed_resource_arns = [
    "arn:aws:redshift-serverless:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*",
    "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*",
    "arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*",
    "arn:aws:s3:::terraform-state-redshift-migration",
    "arn:aws:s3:::terraform-state-redshift-migration/*"
  ]
  
  # Auto-scaling configuration
  enable_auto_scaling = var.enable_auto_scaling
  min_replicas        = var.min_replicas
  max_replicas        = var.max_replicas
  
  environment = var.environment
  tags        = local.common_tags
  
  depends_on = [module.foundation_network]
}

# Optional: Bastion host for debugging
module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "./modules/bastion"
  
  vpc_id            = module.foundation_network.vpc_id
  public_subnet_id  = module.foundation_network.public_subnet_ids[0]
  allowed_ips       = var.bastion_allowed_ips
  key_name          = var.bastion_key_name
  
  environment = var.environment
  tags        = local.common_tags
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = merge(
    {
      Environment  = var.environment
      Project      = var.project_name
      ManagedBy    = "Terraform"
      Owner        = "DevOps"
      CostCenter   = "${var.project_name}-${var.environment}"
      Organization = var.organization
      Purpose      = "Bootstrap-Infrastructure"
    },
    var.additional_tags
  )
}