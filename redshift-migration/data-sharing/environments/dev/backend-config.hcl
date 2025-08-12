# Backend configuration for dev environment
bucket         = "terraform-state-redshift-migration"
key            = "redshift-data-sharing/dev/terraform.tfstate"
region         = "us-west-2"
encrypt        = true
dynamodb_table = "terraform-state-locks"