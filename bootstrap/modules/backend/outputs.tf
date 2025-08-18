output "bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "kms_key_id" {
  description = "KMS key ID for state encryption"
  value       = aws_kms_key.terraform_state.id
}

output "kms_key_arn" {
  description = "KMS key ARN for state encryption"
  value       = aws_kms_key.terraform_state.arn
}

output "backend_policy_arn" {
  description = "ARN of the IAM policy for backend access"
  value       = aws_iam_policy.terraform_backend_access.arn
}

output "backend_config" {
  description = "Terraform backend configuration to use in other projects"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    key            = "terraform.tfstate"  # This should be customized per project
    region         = data.aws_region.current.name
    encrypt        = true
    kms_key_id     = aws_kms_key.terraform_state.arn
    dynamodb_table = aws_dynamodb_table.terraform_locks.id
  }
}

data "aws_region" "current" {}