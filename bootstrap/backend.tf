# Backend configuration for bootstrap infrastructure
# Using the same S3 bucket but different state file path

terraform {
  backend "s3" {
    bucket         = "terraform-state-redshift-migration"
    key            = "bootstrap/terraform.tfstate"  # Different path from data-sharing
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}