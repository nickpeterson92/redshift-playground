# Bootstrap Infrastructure for Harness Delegate

This directory contains the foundational infrastructure that must be deployed BEFORE Harness can manage your application deployments.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Harness Platform (SaaS)              │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS/gRPC
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    Foundation VPC                       │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Private Subnets (Multi-AZ)            │   │
│  │  ┌─────────────────────────────────────────┐     │   │
│  │  │     ECS Fargate - Harness Delegate      │     │   │
│  │  │         (2+ replicas for HA)            │     │   │
│  │  └─────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Public Subnets (Multi-AZ)             │   │
│  │     NAT Gateways │ Internet Gateway              │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Application Infrastructure                 │
│     (Redshift, NLB, etc. - Managed by Harness)          │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. Foundation Network (`modules/networking/`)
- Persistent VPC that hosts all infrastructure
- Public/Private subnets across multiple AZs
- NAT Gateways for outbound internet access
- VPC Endpoints for AWS services (S3, ECR)

### 2. Terraform Backend (`modules/backend/`)
- S3 bucket for Terraform state storage
- DynamoDB table for state locking
- KMS encryption for security
- IAM policies for access control

### 3. Harness Delegate (`modules/harness-delegate/`)
- ECS Fargate cluster and service
- Auto-scaling configuration for high availability
- IAM roles with permissions to manage:
  - Redshift Serverless resources
  - EC2 and networking components
  - Load balancers
  - Terraform state in S3

### 4. Optional Bastion Host (`modules/bastion/`)
- EC2 instance for debugging and manual access
- PostgreSQL client pre-installed
- Security group with IP allowlist

## Deployment Steps

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0 installed
3. Harness account with delegate token

### Step 1: Prepare Configuration

```bash
cd bootstrap/

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# - harness_account_id: From Harness platform
# - harness_delegate_token: Generated in Harness UI
# - organization: Your company name
# - environment: dev/staging/prod
```

### Step 2: Deploy Bootstrap Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy (this creates VPC, delegate, and backend)
terraform apply

# Save the outputs for later use
terraform output -json > bootstrap-outputs.json
```

### Step 3: Configure Application Terraform

After bootstrap completes, update your application's Terraform configuration:

```hcl
# In redshift-migration/data-sharing/backend.tf
terraform {
  backend "s3" {
    bucket         = "mycompany-dev-terraform-state"  # From bootstrap output
    key            = "redshift/terraform.tfstate"     # Unique per project
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:..."               # From bootstrap output
    dynamodb_table = "mycompany-dev-terraform-state-locks"
  }
}
```

### Step 4: Update Application Variables

```hcl
# In redshift-migration/data-sharing/terraform.tfvars
vpc_id     = "vpc-xxx"        # From bootstrap output
subnet_ids = ["subnet-xxx"]   # From bootstrap output
```

### Step 5: Verify Delegate Connection

1. Go to Harness Platform UI
2. Navigate to Project Settings → Delegates
3. Verify your delegate shows as "Connected"
4. Check CloudWatch logs if issues:
   ```bash
   aws logs tail /ecs/mycompany-dev-delegate --follow
   ```

## Managing the Infrastructure

### Updating Delegate

```bash
# Update delegate version or configuration
terraform apply -target=module.harness_delegate

# Scale delegate replicas
terraform apply -var="delegate_replicas=3"
```

### Cost Optimization

For non-production environments:
- Set `single_nat_gateway = true` (saves ~$45/month per extra NAT)
- Reduce `delegate_replicas = 1` (saves ~$20/month)
- Use smaller delegate size: `delegate_cpu = "512"` 

### Monitoring

Check delegate health:
```bash
# View ECS service status
aws ecs describe-services \
  --cluster mycompany-dev-delegate-cluster \
  --services mycompany-dev-delegate

# View delegate logs
aws logs tail /ecs/mycompany-dev-delegate --follow
```

### Destroying Infrastructure

⚠️ **WARNING**: Only destroy bootstrap after migrating or removing all application resources!

```bash
# First, destroy application infrastructure via Harness
# Then destroy bootstrap:
terraform destroy
```

## Security Considerations

1. **Network Isolation**: Delegate runs in private subnets
2. **Encryption**: All state files encrypted with KMS
3. **IAM Least Privilege**: Delegate only has required permissions
4. **No Inbound Access**: Delegate initiates outbound connections only
5. **Secrets Management**: Use AWS Secrets Manager for sensitive data

## Troubleshooting

### Delegate Not Connecting
- Check security groups allow outbound 443
- Verify NAT Gateway is working
- Check delegate token is correct
- Review CloudWatch logs for errors

### Terraform State Issues
- Ensure S3 bucket exists and is accessible
- Verify DynamoDB table for locking
- Check IAM permissions for state access

### Cost Alerts
- Set up AWS Budget alerts for unexpected charges
- Monitor NAT Gateway data transfer costs
- Review ECS Fargate usage

## Next Steps

After bootstrap deployment:
1. Create Harness pipelines for application deployments
2. Configure Harness environments (dev/staging/prod)
3. Set up Harness triggers and workflows
4. Implement GitOps with your repository