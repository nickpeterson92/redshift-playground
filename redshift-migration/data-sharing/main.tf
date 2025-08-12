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
  
  vpc_name    = var.vpc_name
  environment = var.environment
  allowed_ip  = var.allowed_ip
}

# Producer namespace for writes (now serverless)
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

# Consumer workgroups for reads
module "consumer_analytics" {
  source = "./modules/consumer"
  
  namespace_name = "${var.project_name}-analytics"
  workgroup_name = "${var.project_name}-analytics-wg"
  database_name  = "analytics_db"
  admin_username = var.master_username
  admin_password = var.master_password
  
  base_capacity = 32
  max_capacity  = 128
  
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.subnet_ids
  security_group_id = module.networking.consumer_security_group_id
  
  environment = var.environment
  purpose     = "analytics"
}

module "consumer_reporting" {
  source = "./modules/consumer"
  
  namespace_name = "${var.project_name}-reporting"
  workgroup_name = "${var.project_name}-reporting-wg"
  database_name  = "reporting_db"
  admin_username = var.master_username
  admin_password = var.master_password
  
  base_capacity = 32
  max_capacity  = 64  # Lower for reporting workload
  
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.subnet_ids
  security_group_id = module.networking.consumer_security_group_id
  
  environment = var.environment
  purpose     = "reporting"
}

# Optional: Additional consumer for ML/Data Science workloads
module "consumer_datascience" {
  source = "./modules/consumer"
  count  = var.enable_datascience_consumer ? 1 : 0
  
  namespace_name = "${var.project_name}-datascience"
  workgroup_name = "${var.project_name}-datascience-wg"
  database_name  = "datascience_db"
  admin_username = var.master_username
  admin_password = var.master_password
  
  base_capacity = 64
  max_capacity  = 256  # Higher for ML workloads
  
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.subnet_ids
  security_group_id = module.networking.consumer_security_group_id
  
  environment = var.environment
  purpose     = "datascience"
}