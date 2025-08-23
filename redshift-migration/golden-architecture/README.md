# Redshift Serverless Data Sharing with Network Load Balancer

🚀 **Production-ready standalone deployment** of AWS Redshift Serverless featuring:
- Self-contained infrastructure (creates own VPC)
- Horizontal scaling through Network Load Balancer (NLB)
- Data sharing patterns with read/write separation
- Snapshot restoration capability
- Comprehensive monitoring and diagnostic tools

## 🎯 Architecture Goals

1. **Separation of Concerns**: Producer handles writes, consumers handle reads
2. **Horizontal Scaling**: Add more consumers as read demand grows
3. **High Availability**: Multiple consumers provide redundancy
4. **Cost Efficiency**: Serverless model with auto-scaling and auto-pause
5. **Load Distribution**: NLB intelligently distributes queries across healthy consumers
6. **Zero Data Movement**: Data sharing without copying or ETL
7. **Independent Scaling**: Each workgroup scales based on its workload
8. **Manual Data Sharing**: Configure data sharing post-deployment via SQL

## Architecture Overview

### Standard Data Sharing Architecture
```
┌─────────────────┐
│   ETL/Writes    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     DATA SHARING
│  Producer       │ ═══════════════════╗
│  (Serverless)   │                    ║
│  32-256 RPUs    │ ════════════════╗  ║
└─────────────────┘                 ║  ║
                                    ▼  ▼
                    ┌─────────────────────┐
                    │  Analytics Consumer │──> Heavy Analytics
                    │  (Serverless)       │    32-128 RPUs
                    └─────────────────────┘
                    ┌─────────────────────┐
                    │  Reporting Consumer │──> BI/Dashboards
                    │  (Serverless)       │    32-64 RPUs
                    └─────────────────────┘
```

### Advanced NLB Architecture (Horizontal Scaling)
```
        ┌─────────────────┐
        │   ETL Pipeline  │
        └────────┬────────┘
                 │ Writes
                 ▼
        ┌─────────────────┐
        │    Producer     │
        │  (Serverless)   │
        │  Write-Only     │
        │   32-256 RPU    │
        └────────┬────────┘
                 │
            DATA │ SHARING
                 │ (Manual Setup)
                 │
    ┌────────────┼────────────┬────────────┐
    │            │            │            │
    ▼            ▼            ▼            ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│Consumer1│ │Consumer2│ │Consumer3│ │ConsumerN│
│Identical│ │Identical│ │Identical│ │Identical│
│ 32 RPU  │ │ 32 RPU  │ │ 32 RPU  │ │ 32 RPU  │
└────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
     │           │           │           │
     └───────────┴─────┬─────┴───────────┘
                       │
                 VPC Endpoints
                       │
            ┌──────────▼──────────┐
            │   Network Load      │
            │   Balancer (NLB)    │
            │  ┌──────────────┐   │
            │  │Target Group  │   │
            │  │Port 5439     │   │
            │  │Health Checks │   │
            │  └──────────────┘   │
            └──────────┬──────────┘
                       │
                   Read Queries
                       │
               ┌───────▼───────┐
               │  Applications │
               │  BI Tools     │
               │  Analytics    │
               └───────────────┘

Note: Data sharing must be configured manually after deployment via SQL commands.
```

## Directory Structure

```
golden-architecture/
├── main.tf                 # Root module orchestration
├── variables.tf           # Input variables (includes VPC creation)  
├── outputs.tf             # Output values & commands
├── terraform.tfvars.example # Example configuration (standalone)
├── backend.tf             # State management config
├── modules/
│   ├── networking/        # VPC, subnets, security groups
│   │   ├── main.tf       # VPC and subnet resources
│   │   ├── outputs.tf    # Network outputs
│   │   └── variables.tf  # Network variables
│   ├── producer/          # Write cluster configuration
│   │   ├── main.tf       # Producer namespace
│   │   ├── outputs.tf    # Producer endpoints
│   │   └── variables.tf  # Producer config
│   ├── consumer/          # Read workgroup template
│   │   ├── main.tf       # Consumer workgroup
│   │   ├── data.tf       # Data sources
│   │   ├── vpc_endpoint.tf # VPC endpoint config
│   │   ├── outputs.tf    # Consumer endpoints
│   │   └── variables.tf  # Consumer config
│   ├── nlb/              # Network Load Balancer
│   │   ├── main.tf       # NLB and target groups
│   │   ├── outputs.tf    # NLB DNS and ARN
│   │   └── variables.tf  # NLB configuration
│   └── snapshot-restore/ # Snapshot restoration module
│       ├── main.tf       # Restoration logic
│       ├── variables.tf  # Configuration
│       └── outputs.tf    # Restoration status
│   └── backend/          # Remote state setup
│       ├── main.tf       # S3 and DynamoDB
│       └── outputs.tf    # Backend config values
├── backend-setup/        # Initial backend creation
│   ├── main.tf          # Standalone backend setup
│   └── README.md        # Setup instructions
├── environments/         # Environment configs
│   └── dev/
│       ├── terraform.tfvars      # Dev variables
│       └── backend-config.hcl    # Backend config
├── test-instance/       # NLB testing infrastructure
│   ├── main.tf         # EC2 test instances
│   ├── instances.tf    # Additional test nodes
│   ├── test-load-balancing.sh # Load test script
│   ├── diagnose.sh     # Connectivity diagnostics
│   └── README.md       # Testing documentation
└── scripts/            # Utility scripts
    ├── deployment/     # Deployment helper scripts
    │   ├── restore-snapshot.sh # Snapshot restoration script
    │   └── deploy.sh   # Main deployment script
    ├── monitoring/     # Monitoring scripts
    │   ├── deploy-monitor-curses.py # Visual deployment monitor
    │   └── FILTERING_LOGIC.md # Resource filtering documentation
    └── utils/          # Utility scripts
        └── check-endpoints.sh # Endpoint verification
```

## ✨ Key Features

### Core Capabilities
- **Modular Terraform Design**: Reusable modules for all components
- **Multi-Environment Support**: Separate configurations for dev/staging/prod
- **Comprehensive Security**: KMS encryption, IAM roles, security groups, VPC isolation
- **Horizontal Scalability**: Add consumers on-demand without downtime
- **Cost Optimization**: Auto-pause, right-sizing, and workload isolation
- **Snapshot Restoration**: Restore existing data from snapshots

### Advanced Features (Production-Ready)
- **Snapshot Restoration**: 
  - Restore existing Redshift snapshots to producer namespace
  - Configurable via terraform variables
  - Supports both cluster and serverless snapshots
- **Network Load Balancer Integration**: 
  - Distributes queries across multiple consumers
  - Health checks ensure only active workgroups receive traffic
  - Connection draining for graceful updates
- **VPC Endpoint Support**:
  - Private connectivity without internet gateway
  - Reduced data transfer costs
  - Enhanced security posture
- **Testing Infrastructure**:
  - EC2-based test instances for validation
  - Load balancing verification scripts
  - Connectivity diagnostics tools

## 🚀 Quick Start

### 1. Set Up Remote State Backend (First Time Only)

```bash
cd golden-architecture/backend-setup
terraform init
terraform apply
# Note the output values for backend configuration
```

### 2. Configure Environment

```bash
cd ../
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings:
# - Set your IP address (get from: curl ifconfig.me)
# - Set a secure password (no default - must be provided)
# - Keep create_vpc = true (default)
# - (Optional) Configure snapshot restoration if you have existing data
```

#### Optional: Restore from Existing Snapshot

If you have an existing Redshift snapshot with the airline_dw data:

```hcl
# In terraform.tfvars
restore_from_snapshot = true
snapshot_identifier   = "airline-data-snapshot"  # Your snapshot name
```

The system will automatically:
- Detect if airline_dw schema already exists
- Restore the snapshot to the producer namespace if needed
- Configure data sharing once data is available

### 3. Deploy Infrastructure

```bash
# Update backend.tf with values from step 1
vim backend.tf  # Add bucket and dynamodb_table values

# Initialize Terraform
terraform init

# Deploy infrastructure
terraform apply
```

**Note**: 
- This creates its own VPC by default. No need for traditional deployment!
- After deployment, configure data sharing manually using SQL commands
- See Data Sharing Setup section below for SQL reference

### 4. Configure Data Sharing (Manual)

After infrastructure is deployed, configure data sharing:

```sql
-- Connect to producer
psql -h <producer-endpoint> -U awsuser -d airline_dw

-- Create datashare (MUST set PUBLICACCESSIBLE for cross-namespace sharing)
CREATE DATASHARE airline_share SET PUBLICACCESSIBLE TRUE;
ALTER DATASHARE airline_share ADD SCHEMA airline_dw;
ALTER DATASHARE airline_share ADD ALL TABLES IN SCHEMA airline_dw;

-- Grant to consumers (repeat for each consumer namespace)
GRANT USAGE ON DATASHARE airline_share TO NAMESPACE '<consumer-namespace-id>';

-- On each consumer, create database from datashare
CREATE DATABASE airline_shared FROM DATASHARE airline_share OF NAMESPACE '<producer-namespace-id>';
```

### 5. Scale Consumers

To add more consumers:

```bash
# Update consumer_count in terraform.tfvars
consumer_count = 5  # Increase from 3

# Apply changes
terraform apply
```

After deployment:
1. Deploy new consumer infrastructure
2. Manually grant datashare access to new consumer namespaces
3. Create database from datashare on new consumers
4. NLB automatically includes new consumers in target group

### 6. Monitor Deployment

```bash
# Real-time deployment monitor with visual feedback
python3 scripts/monitoring/deploy-monitor-curses.py

# Traditional monitoring
./scripts/monitoring/monitor-deployment.sh
```

### 7. Test NLB Connectivity

```bash
# Deploy test infrastructure
cd test-instance
terraform init && terraform apply

# Run load balancing test
./test-load-balancing.sh

# Diagnose any issues
./diagnose.sh
```

## 🌐 Network Configuration Options

### Default: Create New VPC (Recommended)
The deployment creates its own VPC by default with proper configuration for Redshift Serverless:

```hcl
# In terraform.tfvars (these are the defaults)
create_vpc     = true
create_subnets = true
vpc_cidr       = "10.0.0.0/16"
subnet_cidrs   = ["10.0.0.0/23", "10.0.2.0/23", "10.0.4.0/23"]
```

### Alternative: Use Existing VPC
If you need to use an existing VPC:

```hcl
# In terraform.tfvars
create_vpc     = false
create_subnets = false
vpc_name       = "existing-vpc-name"  # Must match Name tag of existing VPC
```

**Requirements for existing VPC**:
- Must have subnets in 3+ availability zones
- Each subnet needs 32+ available IPs
- DNS hostnames and DNS resolution enabled

## 📦 Module Details

### Snapshot Restore Module
- **Snapshot Restoration**:
  - Restores existing snapshots to producer namespace
  - Runs during `terraform apply` if configured
  - Supports both cluster and serverless snapshots
- **Configuration**:
  - Enable via `restore_from_snapshot = true`
  - Specify snapshot with `snapshot_identifier`
  - Force re-restore with `force_restore = true`
- **Validation**:
  - Checks if data already exists before restoring
  - Provides restoration status in outputs
  - Handles errors gracefully

### Networking Module
- **VPC Management**: Creates or uses existing VPC
- **Subnet Configuration**: 
  - Private subnets across 3 AZs (required)
  - /23 CIDR blocks for adequate IP space
  - Proper route table associations
- **Security Groups**:
  - Producer: Allows inbound from consumers
  - Consumer: Allows outbound to producer
  - NLB: Health check and client access

### Producer Module  
- **Serverless Configuration**:
  - Base capacity: 32 RPUs (configurable)
  - Max capacity: 256 RPUs (auto-scaling)
  - Auto-pause after 10 minutes idle
- **Security**:
  - KMS encryption at rest
  - IAM role for S3 and data sharing
  - Private subnet deployment
- **Data Sharing**:
  - Manual datashare configuration required
  - SQL commands provided in documentation

### Consumer Module
- **Serverless Workgroups**:
  - Configurable base/max RPU capacity
  - Identical sizing for NLB load distribution
  - Auto-pause configuration
- **VPC Endpoints**:
  - Automatic endpoint creation
  - IP address management for NLB targets
  - DNS resolution for private access
- **Data Access**:
  - Manual database creation from datashare required
  - Access available after SQL configuration

### NLB Module
- **Load Balancer Configuration**:
  - Internal NLB for private access
  - Cross-zone load balancing
  - Connection draining (30s default)
- **Target Group**:
  - Port 5439 (Redshift)
  - TCP protocol
  - Health checks every 30 seconds
- **Target Registration**:
  - Automatic VPC endpoint IP discovery
  - Dynamic target updates
  - Availability zone awareness

## 🔧 Customization

### Adjust Consumer Capacity

```hcl
# In terraform.tfvars
consumer_base_capacity = 64   # Increase base RPUs
consumer_max_capacity  = 256  # Increase max RPUs
```

### Environment-Specific Settings

Each environment can have different:
- RPU limits
- Network configurations
- Number of consumers
- Auto-pause settings

## 📋 Best Practices

1. **Credentials**: Never hardcode passwords - use variables or AWS Secrets Manager
2. **Networking**: Keep producer in private subnet
3. **Monitoring**: Set up CloudWatch alarms for RPU usage
4. **Backup**: Configure snapshot policies
5. **Access**: Use IAM authentication when possible
6. **Scaling**: Remember to configure data sharing for new consumers

## 💰 Cost Optimization

### Serverless Pricing Model
- **Base Rate**: $0.36/RPU-hour (as of 2024)
- **Billing**: Per-second with 60-second minimum
- **Auto-pause**: Zero cost when idle

### Cost Strategies
1. **Right-size RPU Capacity**:
   - Start with minimum viable RPUs
   - Monitor performance metrics
   - Adjust based on actual usage

2. **Aggressive Auto-pause**:
   - Development: 5-10 minutes
   - Staging: 10-30 minutes  
   - Production: 30-60 minutes

3. **Workload Isolation**:
   - Separate high/low priority workloads
   - Different RPU allocations per workload
   - Cost allocation by team/project

### Example Monthly Costs
- **Producer (32 RPU, 8hr/day)**: ~$276
- **3 Consumers (32 RPU each, 4hr/day)**: ~$414
- **Total**: ~$690/month

## 🔍 Troubleshooting

### Monitoring Tools

#### Real-time Deployment Monitor
```bash
# Visual deployment monitor with progress tracking
python3 scripts/monitoring/deploy-monitor-curses.py

# Traditional status monitor
./scripts/monitoring/monitor-deployment.sh
```

Shows:
- Current status of all workgroups and namespaces
- Data sharing configuration progress
- VPC endpoint states
- Elapsed time and progress indicators

### Common Issues & Solutions

1. **Data Sharing Not Working - No airline_dw Schema**
   - **Cause**: Producer doesn't have the airline_dw schema (no snapshot restored)
   - **Check**: Connect to producer and verify schema exists
   - **Solutions**:
     a. Restore from snapshot:
     ```hcl
     # In terraform.tfvars
     restore_from_snapshot = true
     snapshot_identifier   = "your-snapshot-name"
     ```
     b. Then run: `terraform apply`
     c. Or manually restore via AWS Console
     d. Then configure data sharing via SQL commands

2. **New Consumer Can't Access Data**
   - **Cause**: Data sharing not configured for new consumer
   - **Solution**: Manually grant datashare access and create database
   - **Verify**: Check consumer can query `airline_shared` database

3. **Subnet Configuration Errors**
   - **Error**: "Subnets must span at least 3 AZs"
   - **Solution**: Ensure you have subnets in 3 different availability zones
   - **Prevention**: Use /23 CIDR blocks for adequate IP space

4. **NLB Target Unhealthy**
   - **Error**: Target health check failing
   - **Solution**: Verify security group allows port 5439
   - **Debug**: Check VPC endpoint is active and has IPs

5. **Connection Timeout via NLB**
   - **Error**: Connection timed out
   - **Solution**: Ensure NLB security group allows your IP
   - **Test**: Use test-instance scripts to validate

6. **Password Issues**
   - **Note**: No default password - must be explicitly set
   - **Solution**: Set `master_password` in terraform.tfvars
   - **Security**: Use strong passwords, consider AWS Secrets Manager

### Useful Commands

```bash
# Check namespace IDs for data sharing configuration
terraform output producer_namespace_id
terraform output consumer_namespace_ids

# Check workgroup status
aws redshiftserverless list-workgroups --query 'workgroups[*].[workgroupName,status]' --output table

# Verify datashare configuration
psql -h <producer-endpoint> -U awsuser -d airline_dw -c "SHOW DATASHARES;"

# Test consumer access
psql -h <consumer-endpoint> -U awsuser -d consumer_db -c "SELECT * FROM svv_all_tables WHERE database_name = 'airline_shared';"
```

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

## 🎯 Data Sharing SQL Reference

### Producer Side Configuration
```sql
-- Create datashare (MUST be PUBLICACCESSIBLE for cross-namespace sharing)
CREATE DATASHARE airline_share SET PUBLICACCESSIBLE TRUE;

-- Add schema to datashare
ALTER DATASHARE airline_share ADD SCHEMA airline_dw;

-- Add all tables in schema
ALTER DATASHARE airline_share ADD ALL TABLES IN SCHEMA airline_dw;

-- View datashares
SHOW DATASHARES;

-- Grant to specific consumer namespace
GRANT USAGE ON DATASHARE airline_share TO NAMESPACE '<consumer-namespace-id>';
```

### Consumer Side Configuration
```sql
-- Create database from datashare
CREATE DATABASE airline_shared FROM DATASHARE airline_share OF NAMESPACE '<producer-namespace-id>';

-- Grant usage to users
GRANT USAGE ON DATABASE airline_shared TO awsuser;

-- Query shared data
SELECT * FROM airline_shared.airline_dw.dim_aircraft LIMIT 10;
```

## 🎯 Next Steps & Advanced Topics

### Creating and Managing Snapshots

#### Create a Snapshot from Traditional Cluster
```bash
# If you have a traditional Redshift cluster with data
aws redshift create-cluster-snapshot \
  --cluster-identifier your-cluster-name \
  --snapshot-identifier airline-data-snapshot
```

#### Create a Snapshot from Serverless
```bash
# From an existing serverless namespace
aws redshift-serverless create-snapshot \
  --namespace-name airline-producer \
  --snapshot-name airline-data-snapshot-v2
```

#### List Available Snapshots
```bash
# Traditional cluster snapshots
aws redshift describe-cluster-snapshots \
  --query 'Snapshots[*].[SnapshotIdentifier,Status,ClusterCreateTime]' \
  --output table

# Serverless snapshots
aws redshift-serverless list-snapshots \
  --query 'snapshots[*].[snapshotName,status,namespaceName]' \
  --output table
```

### Immediate Priorities
1. **Monitoring & Observability**:
   - CloudWatch dashboards for RPU usage
   - Query performance monitoring
   - Cost tracking and alerts

2. **Backup & Recovery**:
   - Automated snapshot schedules
   - Cross-region snapshot copying
   - Point-in-time recovery testing

### Advanced Implementations
3. **Performance Optimization**:
   - Materialized views for common queries
   - Result caching strategies
   - Workload management (WLM) queues

4. **Security Enhancements**:
   - Row-level security (RLS)
   - Column-level encryption
   - Audit logging to S3

5. **Multi-Region Setup**:
   - Cross-region data sharing
   - Disaster recovery planning
   - Global load balancing

## 📚 Key Features of This Deployment

### Infrastructure as Code
- **Modular Design**: Reusable Terraform modules for all components
- **Single Command Deployment**: `terraform apply` deploys all infrastructure
- **Self-Documenting**: Infrastructure as code documents the setup
- **Rollback Safe**: Terraform manages state for easy rollback

### Production Readiness
- **High Availability**: Multiple consumers with load balancing
- **Monitoring Built-in**: Visual deployment monitor with real-time status
- **Security**: VPC isolation, security groups, IAM roles
- **Cost Optimization**: Auto-pause and right-sizing capabilities

### Scalability
- **Horizontal Scaling**: Add consumers on-demand
- **Load Distribution**: NLB automatically distributes queries
- **Independent Scaling**: Each workgroup scales based on workload
- **Zero Data Movement**: Data sharing without copying

## 📖 Additional Resources

### Documentation
- [AWS Redshift Serverless Guide](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless.html)
- [Data Sharing Documentation](https://docs.aws.amazon.com/redshift/latest/dg/datashare.html)
- [Network Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)

### Related Files
- [Test Instance README](test-instance/README.md)
- [Backend Setup Guide](backend-setup/README.md)
- [Environment Configuration](environments/README.md)
- [Monitoring Documentation](scripts/monitoring/FILTERING_LOGIC.md)

## 🐛 Known Issues & Limitations

- **NLB Health Checks**: Require VPC internal access (security group rule must allow port 5439)
- **Password Requirements**: Redshift passwords cannot contain @, ", /, \, or space characters
- **Data Sharing**: Requires `PUBLICACCESSIBLE TRUE` flag on datashare creation
- **Subnet Requirements**: Must have subnets in 3+ availability zones for Redshift Serverless

## 🤝 Contributing

This is a learning playground - feel free to experiment, break things, and learn!