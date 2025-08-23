# Redshift Traditional Deployment

This deployment creates a traditional Redshift cluster setup with a producer-consumer architecture built on top of the bootstrap infrastructure.

## Architecture

The deployment creates:
- **1 Producer Cluster** - Central data warehouse that owns and manages all data
- **2 Consumer Clusters** - Domain-specific clusters for isolated workloads:
  - **Sales/Marketing Domain** - For sales and marketing analytics
  - **Operations/Analytics Domain** - For operational analytics and reporting

## Features

- **Data Sharing Ready**: Clusters are configured with namespace IDs for Redshift data sharing
- **Cost Optimized**: Uses ra3.xlplus nodes (single-node by default for development)
- **Secure by Default**: Leverages bootstrap VPC and private subnets
- **IAM Integration**: Configured with IAM roles for S3 access
- **Flexible Configuration**: Separate settings for producer and consumer clusters

## Prerequisites

1. Bootstrap infrastructure must be deployed first:
   ```bash
   cd ../../bootstrap
   terraform init
   terraform apply
   ```

2. AWS credentials configured with appropriate permissions

## Deployment

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Review the configuration:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your settings
   ```

3. Plan the deployment:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

## Configuration

Key variables in `terraform.tfvars`:

- `environment` - Environment name (dev/staging/prod)
- `master_password` - Master password for all clusters (change from default!)
- `node_type` - Producer cluster node type
- `consumer_node_type` - Consumer clusters node type
- `publicly_accessible` - Whether clusters are publicly accessible
- `encrypt_cluster` - Enable encryption for production

## Data Sharing Setup

After deployment, you can set up data sharing between producer and consumer clusters:

1. On the **Producer Cluster**, create a datashare:
   ```sql
   -- Connect to producer cluster
   CREATE DATASHARE sales_share;
   ALTER DATASHARE sales_share ADD SCHEMA sales_schema;
   ALTER DATASHARE sales_share ADD ALL TABLES IN SCHEMA sales_schema;
   GRANT USAGE ON DATASHARE sales_share TO NAMESPACE '<consumer_sales_namespace_id>';
   ```

2. On the **Consumer Cluster**, create a database from the datashare:
   ```sql
   -- Connect to consumer cluster
   CREATE DATABASE sales_db FROM DATASHARE sales_share OF NAMESPACE '<producer_namespace_id>';
   ```

## Outputs

The deployment provides connection information for all clusters:

- Producer cluster endpoint, JDBC connection string, and psql command
- Consumer Sales cluster connection details
- Consumer Operations cluster connection details
- Namespace IDs for data sharing configuration

## Cost Optimization

Default configuration is optimized for development:
- Single-node clusters (ra3.xlplus)
- Minimal snapshot retention (1 day)
- No encryption (enable for production)

For production, consider:
- Multi-node clusters for high availability
- Longer snapshot retention (7-30 days)
- Encryption enabled
- Logging to S3

## Files

- `main.tf` - Main Terraform configuration
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `backend.tf` - S3 backend configuration
- `terraform.tfvars` - Variable values (create from example)
- `terraform.tfvars.example` - Example configuration

## Cleanup

To destroy the resources:
```bash
terraform destroy
```

Note: This will delete all clusters and their data. Ensure you have backups if needed.