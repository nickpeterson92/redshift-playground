# Remote state configuration
# This file configures S3 backend for Terraform state

terraform {
  backend "s3" {
    # Configuration will be provided via backend-config during init
    # terraform init -backend-config=environments/dev/backend-config.hcl
  }
}