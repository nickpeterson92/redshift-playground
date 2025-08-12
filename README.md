# Redshift Migration & Data Sharing Architecture

This project demonstrates a complete migration from traditional Redshift to a modern serverless architecture with read/write separation using Redshift Data Sharing.

## Project Structure

```
redshift-migration/
├── traditional/              # Traditional Redshift cluster deployment
│   ├── redshift.tf          # VPC + cluster infrastructure (with 3 AZs)
│   └── terraform.tfvars     # Configuration values
├── serverless/              # Standalone Redshift Serverless
│   ├── redshift-serverless.tf
│   └── terraform.tfvars
├── data-sharing/            # Production data sharing architecture
│   ├── modules/             # Terraform modules
│   │   ├── producer/        # Serverless namespace for writes
│   │   ├── consumer/        # Serverless namespace for reads
│   │   ├── networking/      # Shared VPC resources
│   │   └── backend/         # State management
│   ├── backend-setup/       # Backend infrastructure setup
│   ├── main.tf              # Main deployment configuration
│   ├── variables.tf         # Variable definitions
│   └── outputs.tf           # Data sharing commands output
├── data-generation/         # Mock airline data generation
│   ├── redshift-airline-schema.sql  # Star schema DDL
│   └── generate-airline-data-simple.py  # Data generator
└── docs/                    # Documentation
```

## Architecture Overview

### Production Architecture (Implemented)
```
                    ┌─────────────────┐
                    │   Producer      │
                    │  (Serverless)   │
                    │  Write Ops      │
                    └────────┬────────┘
                             │
                      Data Sharing
                             │
                ┌────────────┴────────────┐
                │                         │
        ┌───────▼────────┐      ┌────────▼────────┐
        │   Analytics    │      │   Reporting     │
        │   Consumer     │      │   Consumer      │
        │   (Read Only)  │      │   (Read Only)   │
        └────────────────┘      └─────────────────┘
```

### Key Components

1. **Producer Namespace** (Write Operations)
   - Serverless: 32-256 RPUs
   - Handles all write operations (ETL, inserts, updates)
   - Owns the source data
   - Manages data sharing permissions

2. **Consumer Namespaces** (Read Operations)
   - Analytics: 32-128 RPUs for complex queries
   - Reporting: 32-64 RPUs for dashboards
   - Read-only access via data sharing
   - Independent scaling and billing

3. **Data Sharing Benefits**
   - No data movement or copying
   - Real-time data access
   - Independent scaling of read/write workloads
   - Cost isolation between teams/workloads

## Migration Path Completed

### ✅ Phase 1: Infrastructure Setup
- Traditional cluster with proper VPC (3 AZs, /23 subnets)
- Serverless data sharing architecture
- Remote state management with S3/DynamoDB

### ✅ Phase 2: Data Loading & Migration
- Generated airline star schema data
- Loaded into traditional cluster
- Created snapshot
- Restored to serverless producer

### ✅ Phase 3: Data Sharing Setup
- Created datashare on producer
- Granted access to consumers
- Created shared databases on consumers
- Verified cross-namespace queries

## Quick Start Guide

### Prerequisites
- AWS account with appropriate permissions
- Terraform >= 1.0
- Python 3.x with psycopg2-binary
- AWS CLI configured

### 1. Deploy Backend Infrastructure
```bash
cd data-sharing/backend-setup
terraform init
terraform apply
# Note the output values for backend configuration
```

### 2. Deploy Traditional Cluster
```bash
cd ../../traditional
terraform init
terraform apply -var="master_password=YourSecurePassword123!"
```

### 3. Load Sample Data
```bash
cd ../data-generation
# Update connection details in script
python generate-airline-data-simple.py
```

### 4. Create Snapshot
```bash
# In AWS Console or CLI
aws redshift create-cluster-snapshot \
  --cluster-identifier my-redshift-cluster \
  --snapshot-identifier airline-data-snapshot
```

### 5. Deploy Data Sharing Architecture
```bash
cd ../data-sharing
# Update backend.tf with values from step 1
terraform init
terraform apply -var="master_password=YourSecurePassword123!"
```

### 6. Restore Snapshot to Producer
```bash
# Use AWS Console to restore snapshot to airline-producer namespace
```

### 7. Setup Data Sharing
```bash
# Run the SQL commands from terraform output on appropriate namespaces
# Producer: CREATE DATASHARE, GRANT USAGE
# Consumers: CREATE DATABASE FROM DATASHARE
```

## Key Features

### Star Schema Design
- **Fact Tables**: flight_operations, bookings, daily_revenue
- **Dimensions**: date, airport, aircraft, customer, flight
- Optimized DISTKEY and SORTKEY for performance

### Cost Optimization
- **Serverless Auto-pause**: No charges when idle
- **Right-sized Consumers**: Different capacities for different workloads
- **Traditional for Learning**: Cheapest fixed-cost option for experimentation

### Security & Compliance
- **VPC Isolation**: Private subnets with security groups
- **IAM Roles**: Least privilege access
- **Encryption**: KMS encryption at rest
- **Data Sharing**: Read-only access for consumers

## Troubleshooting

### Common Issues

1. **"Publicly accessible consumer" error**
   ```sql
   -- On producer namespace
   ALTER DATASHARE airline_share SET PUBLICACCESSIBLE TRUE;
   ```

2. **Insufficient IP addresses**
   - Ensure subnets are /23 or larger
   - Need 3 subnets in different AZs

3. **Snapshot restore issues**
   - Ensure target namespace exists
   - Check IAM permissions
   - Verify KMS key access

## Cost Estimates

### Traditional Cluster
- ra3.xlplus: ~$414/month (24/7)
- Best for: Learning, development

### Serverless (Per Namespace)
- Base (32 RPU): $11.52/hour when active
- Scales up to configured maximum
- Auto-pauses when idle
- Best for: Production workloads

### Example Monthly Costs
- Producer (8 hours/day): ~$276/month
- Analytics (4 hours/day): ~$138/month  
- Reporting (2 hours/day): ~$69/month
- **Total**: ~$483/month with isolation and scaling

## Lessons Learned

1. **VPC Requirements**: Redshift Serverless needs 3 AZs and ample IP space
2. **Data Sharing Gotchas**: Public workgroups need explicit datashare permissions
3. **Primary Keys**: Always include primary keys in fact table inserts
4. **State Management**: Use remote state for team collaboration
5. **Module Design**: Modular Terraform enables reusable components

## Next Steps

- [ ] Implement automated ETL to producer
- [ ] Set up monitoring and alerting
- [ ] Add cross-region disaster recovery
- [ ] Implement data lifecycle policies
- [ ] Create cost allocation tags

## Contributing

Feel free to submit issues and enhancement requests!

## License

This is a demonstration project for learning purposes.