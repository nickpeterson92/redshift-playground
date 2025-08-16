# Environment Configurations

This directory contains environment-specific configurations for the Redshift data sharing deployment.

## Directory Structure

```
environments/
├── README.md                    # This file
├── terraform.tfvars.example     # Template for environment variables
├── backend-config.hcl.example   # Template for backend configuration
└── dev/                         # Development environment
    ├── terraform.tfvars         # Dev-specific variables
    ├── terraform.tfvars.example # Dev example (for reference)
    └── backend-config.hcl      # Dev backend configuration
```

## Setting Up a New Environment

To create a new environment (e.g., staging or production):

### 1. Create Environment Directory
```bash
mkdir staging  # or prod
```

### 2. Copy Templates
```bash
cp terraform.tfvars.example staging/terraform.tfvars
cp backend-config.hcl.example staging/backend-config.hcl
```

### 3. Configure Variables
Edit `staging/terraform.tfvars`:
- Set `environment = "staging"`
- Update capacity settings for your workload
- Set your secure password
- Configure network settings

### 4. Configure Backend
Edit `staging/backend-config.hcl`:
- Set unique state file key: `key = "redshift-data-sharing/staging/terraform.tfstate"`
- Ensure bucket and DynamoDB table names match your backend setup

### 5. Deploy
From the main data-sharing directory:
```bash
# Initialize with environment-specific backend
terraform init -backend-config=environments/staging/backend-config.hcl

# Deploy with environment-specific variables
terraform apply -var-file=environments/staging/terraform.tfvars
```

## Environment Recommendations

### Development
- **Purpose**: Development and testing
- **Consumers**: 2 (minimize costs)
- **Capacity**: 32-64 RPUs (minimal)
- **Auto-pause**: 10 minutes
- **Cost**: ~$100-200/month with auto-pause

### Staging
- **Purpose**: Pre-production testing
- **Consumers**: 3 (test load balancing)
- **Capacity**: 32-128 RPUs (moderate)
- **Auto-pause**: 30 minutes
- **Cost**: ~$300-500/month

### Production
- **Purpose**: Production workloads
- **Consumers**: 3-5 (based on load)
- **Capacity**: 64-256 RPUs (high)
- **Auto-pause**: 60 minutes or disabled
- **Cost**: ~$1000-3000/month

## Best Practices

1. **Separate State Files**: Each environment must have its own state file path
2. **Secure Passwords**: Never commit passwords to git - use AWS Secrets Manager in production
3. **IP Restrictions**: Update `allowed_ip` for each environment's access requirements
4. **Capacity Planning**: Start small and scale based on actual usage metrics
5. **Cost Monitoring**: Set up CloudWatch billing alerts for each environment

## Switching Between Environments

To switch between environments:

```bash
# Clean up local state references
rm -rf .terraform/

# Initialize for new environment
terraform init -backend-config=environments/prod/backend-config.hcl

# Apply with environment-specific variables
terraform apply -var-file=environments/prod/terraform.tfvars
```

## Important Notes

- **State Isolation**: Never share state files between environments
- **Backend First**: Always run `backend-setup/` before creating any environment
- **Version Control**: Commit `.example` files, but never actual `terraform.tfvars` with passwords
- **Snapshot Management**: Consider separate snapshots for each environment