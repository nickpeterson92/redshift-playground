# AWS Redshift Migration Playground

A comprehensive playground for exploring AWS Redshift deployment patterns, data sharing, and horizontal scaling with Network Load Balancer (NLB).

## 🎯 Purpose

This repository demonstrates:
- Traditional Redshift cluster deployment
- Modern Redshift Serverless architecture with data sharing
- Horizontal scaling using NLB for query distribution
- Infrastructure as Code using Terraform
- Best practices for production-ready deployments

## 📁 Repository Structure

```
redshift-migration/
├── traditional/           # Traditional provisioned Redshift cluster
├── data-sharing/         # Redshift Serverless with NLB and data sharing
│   ├── modules/          # Terraform modules (producer, consumer, nlb, networking)
│   ├── environments/     # Environment-specific configurations
│   └── test-instance/    # EC2 instances for testing NLB connectivity
└── data-generation/      # Scripts for generating sample airline data
```

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Python 3.x (for data generation scripts)
- psql or AWS Query Editor for database access

### 1. Deploy Data Sharing Architecture

```bash
cd data-sharing

# Copy and configure your environment
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize and deploy
terraform init -backend-config=environments/dev/backend-config.hcl
terraform apply
```

### 2. Deploy Test Instances (Optional)

```bash
cd test-instance
terraform init
terraform apply

# Test NLB load balancing
./test-load-balancing.sh
```

### 3. Generate Sample Data

```bash
cd data-generation
python3 generate-airline-data-simple.py
```

## 🏗️ Architecture Overview

### Data Sharing Architecture

```
┌─────────────────┐
│    Producer     │ ← Writes (ETL, Data Ingestion)
│   (Serverless)  │
│  airline_dw DB  │
└────────┬────────┘
         │ Data Share
    ┌────┴────┬──────────┐
    ↓         ↓          ↓
┌────────┐ ┌────────┐ ┌────────┐
│Consumer│ │Consumer│ │Consumer│ ← Reads (Analytics, BI)
│   1    │ │   2    │ │   N    │
└────────┘ └────────┘ └────────┘
    ↑         ↑          ↑
    └────────┬───────────┘
         [  NLB  ]
             ↑
         Queries from Applications
```

### Key Features

- **Producer Workgroup**: Handles all write operations
- **Consumer Workgroups**: Read-only access via data sharing
- **Network Load Balancer**: Distributes queries across consumers
- **Auto-scaling**: Each workgroup scales independently (32-256 RPU)
- **High Availability**: Multiple consumers for redundancy

## 📊 Data Model

The sample airline data warehouse includes:

### Dimension Tables
- `dim_aircraft` - Aircraft fleet information
- `dim_airport` - Airport details and hub status
- `dim_customer` - Customer profiles and loyalty tiers
- `dim_date` - Date dimension for time-based analysis
- `dim_flight` - Flight routes and schedules

### Fact Tables
- `fact_bookings` - Booking transactions
- `fact_flights` - Flight operations and delays

## 🔧 Configuration

### Environment Variables

Create `terraform.tfvars` from the example:

```hcl
aws_region      = "us-west-2"
project_name    = "airline"
environment     = "dev"
master_username = "admin"
master_password = "YourSecurePassword123!"  # REQUIRED - no default, must be set!
allowed_ip      = "YOUR.IP.HERE/32"
consumer_count  = 2  # Number of consumer workgroups
```

### Scaling Configuration

Adjust in `main.tf`:

```hcl
locals {
  consumer_base_capacity = 32   # Minimum RPUs
  consumer_max_capacity  = 128  # Maximum RPUs
}
```

## 🧪 Testing

### Test NLB Connectivity

```bash
# From test-instance directory
export REDSHIFT_PASSWORD='YourActualPassword'  # Use the password from terraform.tfvars
./run-remote-test.sh         # Quick connectivity test
./run-remote-test.sh python  # Load distribution test
./test-load-balancing.sh     # Test from both EC2 instances
```

### Query Through NLB

```sql
-- Connect via NLB endpoint
psql -h <nlb-endpoint> -p 5439 -U admin -d consumer_db

-- Query shared data
SELECT * FROM airline_shared.airline_dw.dim_aircraft LIMIT 10;
```

## 📈 Monitoring

- **AWS Console**: Monitor workgroup metrics, query performance
- **CloudWatch**: Set up alarms for RPU usage, query queue time
- **Query Editor**: Test queries and validate data sharing

## 🔒 Security

- All passwords stored in `.tfvars` (never committed)
- VPC isolation with security groups
- SSL/TLS encryption for all connections
- IAM roles for service permissions
- Data sharing uses namespace-level grants

## 💰 Cost Optimization

- Serverless charges only for active RPU-hours
- Start with minimum base capacity (32 RPU)
- Auto-scaling handles peak loads
- Pause workgroups when not in use

## 🐛 Known Issues

- AWS limit: Creating 4+ concurrent workgroups may cause issues
- NLB health checks require VPC internal access (security group rule)
- Redshift passwords cannot contain certain special characters

## 📚 Additional Resources

- [AWS Redshift Serverless Documentation](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless.html)
- [Redshift Data Sharing Guide](https://docs.aws.amazon.com/redshift/latest/dg/datashare.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## 🤝 Contributing

This is a learning playground - feel free to experiment, break things, and learn!

## 📝 License

This is a personal learning project. Use at your own risk.