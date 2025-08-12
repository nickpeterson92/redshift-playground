# Redshift Terraform Deployment

This is a minimal cost Redshift cluster configuration using Terraform.

## Cost Optimization Settings

- **Node Type**: `dc2.large` (cheapest available)
- **Cluster Type**: Single-node (no multi-node cluster costs)
- **Snapshots**: Disabled (retention = 0)
- **Encryption**: Disabled (can enable if needed)

## Estimated Costs

- **dc2.large single node**: ~$0.25/hour or ~$180/month (varies by region)
- **Storage**: 160GB SSD included with dc2.large
- **No additional snapshot storage costs**

## Usage

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your password

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Plan the deployment:
   ```bash
   terraform plan
   ```

5. Apply:
   ```bash
   terraform apply
   ```

## Security Notes

- Cluster is not publicly accessible by default
- Update security group CIDR blocks for your IP range
- Use a strong password
- Consider enabling encryption for production

## Clean Up

To avoid charges:
```bash
terraform destroy
```