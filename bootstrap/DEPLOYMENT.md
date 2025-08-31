# Simple Deployment Guide

## Backend Setup

**We're using your EXISTING backend!**

- S3 Bucket: `terraform-state-redshift-migration`
- DynamoDB Table: `terraform-state-locks`
- Region: `us-west-2`

## Step 1: Deploy Bootstrap Infrastructure

```bash
cd bootstrap/

# Configure your settings
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Harness credentials

# Initialize with existing backend
terraform init

# Deploy (creates VPC and delegate only)
terraform apply
```

## Step 2: Configure Data-Sharing to Use Bootstrap VPC

```bash
cd ../redshift-migration/data-sharing/

# Update your terraform.tfvars
cat >> terraform.tfvars <<EOF
# Use bootstrap VPC
create_vpc     = false
vpc_name       = "redshift-vpc-dev"
create_subnets = false
EOF

# Your backend.tf already exists and points to the right bucket!
# Just init and you're ready
terraform init -backend-config=environments/dev/backend-config.hcl
```

## State File Organization

Both deployments use the SAME S3 bucket with DIFFERENT paths:

```markdown
s3://terraform-state-redshift-migration/
├── bootstrap/terraform.tfstate              # Bootstrap infrastructure
└── redshift-data-sharing/dev/terraform.tfstate  # Your existing data-sharing
```

## That's It

- Bootstrap creates VPC named `redshift-vpc-dev` and Harness delegate
- Data-sharing finds the VPC by name  
- Both use the same backend bucket (different state files)
- Harness can deploy your Redshift infrastructure
