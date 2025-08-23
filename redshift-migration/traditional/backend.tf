terraform {
  backend "s3" {
    bucket         = "terraform-state-redshift-migration"
    key            = "traditional/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}