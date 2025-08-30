# CLAUDE.md - Redshift Migration Playground Context

## Project Overview
This is a comprehensive AWS Redshift migration playground demonstrating modern data warehouse architectures with horizontal scaling, data sharing, and serverless deployments.

## Directory Structure
```
redshift-playground/
├── bootstrap/                    # Base infrastructure setup
│   ├── main.tf                          # VPC, networking, IAM roles
│   ├── outputs.tf                       # Infrastructure outputs
│   ├── terraform.tfvars                 # Bootstrap configuration
│   └── modules/                  # Bootstrap modules
│       ├── backend/                     # Terraform backend setup
│       ├── bastion/                     # Bastion host configuration
│       ├── harness-delegate/            # Harness CI/CD delegate
│       └── networking/                  # VPC and subnet configuration
│
├── redshift-migration/           # Main migration project
│   ├── data-generation/          # Data generation utilities
│   │   ├── generate-multi-domain-data.py    # Multi-domain test data generator
│   │   └── setup-data-sharing.py            # Data sharing configuration script
│   │
│   ├── docs/                     # Documentation
│   │   ├── connection-guide.md              # Database connection guide
│   │   ├── golden-architecture-patterns.md  # Architecture patterns
│   │   └── migration-strategy.md            # Migration strategies
│   │
│   ├── golden-architecture/      # Modern serverless architecture
│   │   ├── main.tf                          # Main Terraform configuration
│   │   ├── outputs.tf                       # Output definitions
│   │   ├── variables.tf                     # Variable definitions
│   │   │
│   │   ├── modules/              # Reusable Terraform modules
│   │   │   ├── consumer/                    # Serverless consumer module
│   │   │   ├── networking/                  # VPC and security groups
│   │   │   ├── nlb/                        # Network Load Balancer
│   │   │   ├── producer/                    # Producer namespace module
│   │   │   └── snapshot-restore/            # Snapshot management
│   │   │
│   │   ├── environments/         # Environment-specific configs
│   │   │   └── dev/                        # Development environment
│   │   │       ├── backend-config.hcl      # Backend configuration
│   │   │       └── terraform.tfvars        # Environment variables
│   │   │
│   │   ├── test-instance/        # EC2-based testing
│   │   │   ├── main.tf                     # Test instance setup
│   │   │   ├── test-load-balancing-remote.py  # Load balancing tests
│   │   │   └── scenarios/                  # Test scenarios
│   │   │
│   │   └── scripts/              # Utility scripts
│   │       ├── deployment/                 # Deployment automation
│   │       └── utils/                      # Troubleshooting utilities
│   │
│   ├── monitoring/               # Monitoring tools
│   │   ├── deploy-monitor-curses.py        # Deployment monitoring
│   │   ├── workgroup-monitor-curses.py     # Workgroup activity monitor
│   │   └── demonstrate-nlb-architecture.sh # NLB demo script
│   │
│   └── traditional/              # Traditional cluster setup
│       ├── main.tf                          # Cluster configuration
│       ├── outputs.tf                       # Output definitions
│       ├── load-test-consumers.py          # Consumer testing
│       └── terraform.tfvars                # Configuration values
│
├── CLAUDE.md                     # This context file
├── README.md                     # Project overview
└── requirements.txt              # Python dependencies
```

## Architecture Components

### 0. Bootstrap Infrastructure (`/bootstrap`)
- **Purpose**: Foundational infrastructure shared across all deployments
- **Components**:
  - VPC with public/private subnets across 3 AZs
  - IAM roles and policies for Redshift
  - S3 buckets for logs and backups
  - Terraform backend configuration
  - Harness Delegate
  - Optional bastion host for secure access
- **Dependency**: Must be deployed first before traditional or golden architecture

### 1. Traditional Deployment (`/redshift-migration/traditional`)
- **Producer Cluster**: Provisioned Redshift cluster hosting all data
- **Consumer Clusters**: 
  - Sales domain consumer
  - Operations domain consumer
- **Pattern**: Traditional 3-cluster setup with domain-specific consumers

### 2. Golden Architecture (`/golden-architecture`)
- **Serverless Consumers**: 3 identical Redshift Serverless workgroups
- **Network Load Balancer**: Distributes queries across consumers
- **Data Sharing**: Receives data from traditional producer
- **Pattern**: Horizontal scaling with automatic load distribution

### 3. Data Model
Three distinct schemas organized by domain:

```sql
-- Shared airline core data (shared with all domains)
shared_airline.airports
shared_airline.aircraft  
shared_airline.flights
shared_airline.routes

-- Sales domain specific
sales_domain.customers
sales_domain.bookings
sales_domain.marketing_campaigns
sales_domain.daily_revenue

-- Operations domain specific
operations_domain.maintenance_logs
operations_domain.crew_assignments
operations_domain.daily_operations_metrics
operations_domain.ground_handling
```

## Key Files and Locations

### Terraform Infrastructure
- `golden-architecture/main.tf` - Main golden architecture configuration
- `golden-architecture/modules/` - Reusable Terraform modules
  - `consumers/` - Serverless consumer configuration
  - `networking/` - VPC and security groups
  - `nlb/` - Network Load Balancer setup
- `golden-architecture/outputs.tf` - Data sharing commands and connection info
- `traditional/main.tf` - Traditional cluster configuration

### Python Scripts
- `data-generation/generate-multi-domain-data.py` - Creates test data across all domains
- `data-generation/setup-data-sharing.py` - Configures data shares
- `monitoring/deploy-monitor-curses.py` - Real-time deployment monitoring
- `monitoring/workgroup-monitor-curses.py` - Workgroup activity monitoring

### Testing
- `golden-architecture/test-instance/` - EC2-based load testing infrastructure
- `traditional/load-test-consumers.py` - Consumer performance testing

## Current State

### Deployed Resources
- **VPC**: Custom VPC with 3 private subnets across AZs
- **Traditional Producer**: Active with multi-domain data
- **Golden Consumers**: 3 serverless workgroups (consumer-1, consumer-2, consumer-3)
- **NLB**: Configured with health checks on port 5439

### Data Sharing Configuration
Three datashares from traditional producer:
1. `airline_core_share` - Core airline data for all consumers
2. `sales_data_share` - Sales domain analytics
3. `operations_data_share` - Operations domain metrics

All shares granted to each golden architecture consumer namespace.

## Common Tasks

### Deploy Bootstrap Infrastructure (Required First)
```bash
cd bootstrap
terraform init
terraform plan
terraform apply
```

### Deploy Traditional Architecture
```bash
cd redshift-migration/traditional
terraform init
terraform plan
terraform apply
```

### Deploy Golden Architecture
```bash
cd redshift-migration/golden-architecture
terraform init
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply var-file=environments/dev/terraform.tfvars
```

### Deploy Test EC2 Instances
```bash
cd redshift-migration/golden-architecture/test-instances
terraform init
terraform plan -var-file=scenarios/small/terraform.tfvars
terraform apply var-file=scenarios/small/terraform.tfvars
```

### Generate Test Data
```bash
cd data-generation
python generate-multi-domain-data.py \
  --host <producer-endpoint> \
  --user awsuser \
  --password <password> \
  --scale medium
```

### Setup Data Sharing
1. Get producer namespace: `SELECT current_namespace;`
2. Create datashares on producer (see `terraform output data_sharing_commands`)
3. Grant to consumer namespaces
4. Create databases on each consumer from shares

### Monitor Deployment
```bash
cd monitoring
python deploy-monitor-curses.py
```

### Test Load Balancing
```bash
cd golden-architecture/test-instance
python test-load-balancing-remote.py \
  --nlb-endpoint <nlb-dns> \
  --password <password>
```

## Important Commands

### Check Data Share Status
```sql
-- On producer
SHOW DATASHARES;
SELECT * FROM SVV_DATASHARES;

-- On consumer  
SHOW DATABASES FROM DATASHARE;
SELECT * FROM SVV_DATASHARE_CONSUMERS;
```

### Verify NLB Targets
```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-west-2
```

### Connect via NLB
```bash
psql -h <nlb-endpoint> -p 5439 -U awsuser -d dev
```

## Troubleshooting

### Common Issues
1. **NLB targets unhealthy**: Check security groups allow port 5439 from NLB to consumers
2. **Data share not visible**: Verify namespace IDs and GRANT statements
3. **Connection timeouts**: Ensure NLB listener and target group use same port (5439)
4. **Terraform state issues**: Use `terraform refresh` to sync state

### Security Groups
- **NLB SG**: Allows inbound 5439 from anywhere (or restricted sources)
- **Consumer SG**: Allows inbound 5439 only from NLB security group
- **Producer SG**: Allows inbound 5439 from specified CIDR blocks