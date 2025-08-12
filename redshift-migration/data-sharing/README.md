# Redshift Data Sharing - Modular Terraform

This is a production-ready, modular Terraform configuration for implementing Redshift data sharing architecture with read/write separation.

## Architecture

```
┌─────────────────┐
│   ETL/Writes    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     DATA SHARING
│  Producer       │ ═══════════════════╗
│  Cluster        │                    ║
│  (RA3 Node)     │ ═══════════════╗  ║
└─────────────────┘                 ║  ║
                                    ▼  ▼
                    ┌─────────────────────┐
                    │  Analytics Consumer │──> Heavy Analytics
                    │  (Serverless)       │
                    └─────────────────────┘
                    ┌─────────────────────┐
                    │  Reporting Consumer │──> BI/Dashboards
                    │  (Serverless)       │
                    └─────────────────────┘
```

## Directory Structure

```
data-sharing-modular/
├── main.tf                 # Root module orchestration
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── modules/
│   ├── networking/        # VPC, subnets, security groups
│   ├── producer/          # Write cluster configuration
│   └── consumer/          # Read workgroup template
└── environments/
    ├── dev/              # Development environment
    ├── staging/          # Staging environment
    └── prod/             # Production environment
```

## Features

- **Modular Design**: Reusable modules for different components
- **Multi-Environment**: Separate configurations for dev/staging/prod
- **Security**: Encrypted clusters, IAM roles, security groups
- **Scalability**: Easy to add more consumer workgroups
- **Cost Optimization**: Serverless consumers with auto-pause

## Quick Start

### 1. Set Up Remote State Backend (First Time Only)

```bash
cd data-sharing
./scripts/setup-backend.sh
```

### 2. Configure Environment

```bash
cp environments/dev/terraform.tfvars environments/dev/terraform.tfvars.local
# Edit terraform.tfvars.local with your settings
```

### 3. Initialize Terraform with Backend

```bash
# Initialize with backend config
terraform init -backend-config=environments/dev/backend-config.hcl

# Create workspace for environment
terraform workspace new dev
```

### 4. Deploy Infrastructure

```bash
# Plan with variables
terraform plan -var-file=environments/dev/terraform.tfvars.local

# Apply
terraform apply -var-file=environments/dev/terraform.tfvars.local
```

### 3. Set Up Data Sharing

After deployment, Terraform will output the exact commands to run:

```bash
terraform output data_sharing_commands
```

## Module Details

### Networking Module
- Manages VPC, subnets, and security groups
- Can use existing VPC or create new one
- Separate security groups for producer and consumers

### Producer Module
- RA3 cluster for write operations
- KMS encryption
- IAM role with S3 access
- Configurable node type and size

### Consumer Module
- Serverless workgroups for read operations
- Auto-scaling with RPU limits
- Workload-specific configurations
- Query timeout settings

## Customization

### Add Another Consumer

1. Add to `main.tf`:
```hcl
module "consumer_ml" {
  source = "./modules/consumer"
  
  namespace_name = "${var.project_name}-ml"
  workgroup_name = "${var.project_name}-ml-wg"
  database_name  = "ml_db"
  # ... other configuration
}
```

2. Update outputs and data sharing commands

3. Apply changes

### Environment-Specific Settings

Each environment can have different:
- Node types and sizes
- RPU limits
- Network configurations
- Number of consumers

## Best Practices

1. **Credentials**: Use AWS Secrets Manager or SSM Parameter Store
2. **Networking**: Keep producer in private subnet
3. **Monitoring**: Set up CloudWatch alarms
4. **Backup**: Configure snapshot policies
5. **Access**: Use IAM authentication when possible

## Cost Optimization

- Producer runs 24/7 (consider reserved instances)
- Consumers auto-pause when idle
- Set appropriate RPU limits
- Monitor usage patterns

## Troubleshooting

### Common Issues

1. **Subnet Error**: Ensure 3+ subnets in different AZs
2. **Namespace Not Found**: Wait for resources to fully deploy
3. **Access Denied**: Check security groups and IAM roles

### Useful Commands

```bash
# Check deployment status
terraform show

# Destroy specific module
terraform destroy -target=module.consumer_reporting

# Import existing resources
terraform import module.producer.aws_redshift_cluster.producer my-existing-cluster
```

## Next Steps

1. Set up monitoring and alerting
2. Implement automated backups
3. Configure cross-region snapshots
4. Add more specialized consumers
5. Implement cost allocation tags