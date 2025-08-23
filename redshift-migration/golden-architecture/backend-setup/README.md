# Backend Setup

This creates the S3 bucket and DynamoDB table needed for Terraform remote state.

## First Time Setup

1. Deploy the backend infrastructure:
```bash
cd backend-setup
terraform init
terraform apply
```

2. Note the output values

3. Update the main `backend.tf` file with the values

## Why Separate?

This is separate from the main deployment because:
- Terraform can't use a backend that doesn't exist yet
- The backend resources need `prevent_destroy` lifecycle rules
- It's a one-time setup that rarely changes

## Resources Created

- S3 bucket with:
  - Versioning enabled
  - Encryption enabled
  - Public access blocked
  - Bucket policy for least privilege

- DynamoDB table with:
  - On-demand billing
  - Used for state locking

Both resources have `prevent_destroy` to avoid accidental deletion.