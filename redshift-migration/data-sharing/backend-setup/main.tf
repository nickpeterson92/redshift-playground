# Separate Terraform configuration to set up backend infrastructure
# Run this first, before the main deployment

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

module "backend" {
  source = "../modules/backend"
  
  bucket_name         = var.state_bucket_name
  dynamodb_table_name = var.lock_table_name
  environment         = "shared"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "state_bucket_name" {
  description = "Name for the state bucket"
  type        = string
  default     = "terraform-state-redshift-migration"
}

variable "lock_table_name" {
  description = "Name for the lock table"
  type        = string
  default     = "terraform-state-locks"
}

output "backend_config" {
  description = "Backend configuration for main deployment"
  value = <<-EOT
    Copy this to your backend.tf:
    
    terraform {
      backend "s3" {
        bucket         = "${module.backend.s3_bucket_name}"
        key            = "redshift-data-sharing/terraform.tfstate"
        region         = "${var.aws_region}"
        encrypt        = true
        dynamodb_table = "${module.backend.dynamodb_table_name}"
      }
    }
  EOT
}