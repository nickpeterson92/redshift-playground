# Remote state configuration
# This file configures S3 backend for Terraform state

terraform {
  backend "s3" {
    bucket         = "terraform-state-redshift-migration"
    key            = "redshift-data-sharing/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
