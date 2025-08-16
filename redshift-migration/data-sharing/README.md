# Redshift Serverless Data Sharing with Network Load Balancer

🚀 **Production-ready standalone deployment** of AWS Redshift Serverless featuring:
- Self-contained infrastructure (creates own VPC)
- Horizontal scaling through Network Load Balancer (NLB)
- Data sharing patterns with read/write separation
- **Automated data sharing setup** for seamless deployment
- Comprehensive monitoring and diagnostic tools

## 🎯 Architecture Goals

1. **Separation of Concerns**: Producer handles writes, consumers handle reads
2. **Horizontal Scaling**: Add more consumers as read demand grows
3. **High Availability**: Multiple consumers provide redundancy
4. **Cost Efficiency**: Serverless model with auto-scaling and auto-pause
5. **Load Distribution**: NLB intelligently distributes queries across healthy consumers
6. **Zero Data Movement**: Data sharing without copying or ETL
7. **Independent Scaling**: Each workgroup scales based on its workload
8. **Automated Setup**: Data sharing configuration happens automatically during deployment

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
                 │ (Automated Setup)
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

Note: Data sharing is configured automatically during deployment.
```

## Directory Structure

```
data-sharing/
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
│   ├── datashare-setup/  # Automated data sharing (NEW!)
│   │   ├── main.tf       # Data sharing automation
│   │   ├── variables.tf  # Configuration
│   │   └── outputs.tf    # Setup status
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
│   ├── second-instance.tf # Additional test node
│   ├── test-load-balancing.sh # Load test script
│   ├── diagnose.sh     # Connectivity diagnostics
│   └── README.md       # Testing documentation
└── scripts/            # Utility scripts
    ├── setup/          # Data sharing setup scripts
    │   ├── setup-datashare.sh    # Automated setup script
    │   ├── 02-configure-datashare.sql # Producer SQL reference
    │   ├── 03-configure-consumers.sql # Consumer SQL reference
    │   └── README.md              # Setup documentation
    ├── monitoring/     # Monitoring scripts
    │   ├── deploy-monitor-curses.py # Deployment monitor
    │   └── monitor-deployment.sh    # Status monitor
    └── testing/        # Test scripts
        └── test-load-balancing.sh # NLB test script
```

## ✨ Key Features

### Core Capabilities
- **Modular Terraform Design**: Reusable modules for all components
- **Multi-Environment Support**: Separate configurations for dev/staging/prod
- **Comprehensive Security**: KMS encryption, IAM roles, security groups, VPC isolation
- **Horizontal Scalability**: Add consumers on-demand without downtime
- **Cost Optimization**: Auto-pause, right-sizing, and workload isolation
- **Automated Data Sharing**: Configuration happens automatically during deployment

### Advanced Features (Production-Ready)
- **Automated Data Sharing Setup**: 
  - Automatically configures producer datashare during deployment
  - Intelligently detects new vs existing consumers
  - Only configures new consumers when scaling
  - Zero manual SQL commands required
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
cd data-sharing/backend-setup
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
```

### 3. Deploy Infrastructure

```bash
# Update backend.tf with values from step 1
vim backend.tf  # Add bucket and dynamodb_table values

# Initialize Terraform
terraform init

# Deploy everything (data sharing is automated!)
terraform apply
```

**Note**: 
- This creates its own VPC by default. No need for traditional deployment!
- Data sharing is automatically configured during deployment
- No manual SQL commands needed

### 4. Verify Data Sharing (Optional)

The data sharing is automatically set up, but you can verify it's working:

```bash
# Check the setup status
terraform output datashare_setup_status

# Connect to any consumer and query shared data
psql -h <consumer-endpoint> -U awsuser -d consumer_db
> SELECT * FROM airline_shared.airline_dw.dim_aircraft LIMIT 5;
```

### 5. Scale Consumers (Automated)

To add more consumers:

```bash
# Update consumer_count in terraform.tfvars
consumer_count = 5  # Increase from 3

# Apply changes - new consumers automatically get data sharing
terraform apply
```

The system will:
- Deploy new consumer infrastructure
- Automatically configure data sharing for new consumers only
- Add them to the NLB target group
- Skip existing consumers (no redundant configuration)

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

### Data Sharing Setup Module (NEW!)
- **Automated Configuration**:
  - Runs automatically during `terraform apply`
  - Creates producer datashare with all required schemas
  - Grants access to consumer namespaces
  - Configures consumer databases from datashare
- **Intelligent Detection**:
  - Checks if consumers already have data sharing configured
  - Only configures new consumers when scaling
  - Prevents redundant operations and errors
- **Manual Override**:
  - Can run setup script manually if needed
  - Supports selective consumer configuration
  - Provides detailed logging and error handling

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
  - Datashare automatically created and configured
  - Access granted to all consumer namespaces

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
  - Automatic database creation from datashare
  - Immediate access to shared data

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
6. **Scaling**: Let automated data sharing handle new consumers

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

1. **Data Sharing Not Configured**
   - **Check**: Run `terraform output datashare_setup_status`
   - **Solution**: The setup runs automatically, but you can trigger manually:
     ```bash
     ./scripts/setup/run-setup.sh
     ```

2. **New Consumer Can't Access Data**
   - **Cause**: Consumer added after initial deployment
   - **Solution**: Run `terraform apply` - automation handles new consumers
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
# Check data sharing setup logs
terraform show -json | jq '.values.root_module.child_modules[] | select(.address == "module.datashare_setup")'

# Manually run data sharing setup
./scripts/setup/setup-datashare.sh $(terraform output -json) --new-consumers-only

# Check workgroup status
aws redshiftserverless list-workgroups --query 'workgroups[*].[workgroupName,status]' --output table

# Verify datashare configuration
psql -h <producer-endpoint> -U awsuser -d airline_dw -c "SHOW DATASHARES;"

# Test consumer access
psql -h <consumer-endpoint> -U awsuser -d consumer_db -c "SELECT * FROM svv_all_tables WHERE database_name = 'airline_shared';"
```

## 🎯 Next Steps & Advanced Topics

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

## 📚 Key Improvements in This Deployment

### Automated Data Sharing
- **Zero Manual Steps**: Data sharing configured automatically during deployment
- **Intelligent Scaling**: New consumers automatically get access to shared data
- **Error Prevention**: No risk of misconfiguration or forgotten steps
- **Idempotent**: Safe to run multiple times, only configures what's needed

### Simplified Operations
- **Single Command Deployment**: `terraform apply` handles everything
- **No SQL Required**: All data sharing SQL executed automatically
- **Self-Documenting**: Infrastructure as code documents the setup
- **Rollback Safe**: Terraform manages state for easy rollback

### Production Readiness
- **Battle-Tested**: Handles edge cases like partial deployments
- **Monitoring Built-in**: Visual feedback during deployment
- **Error Recovery**: Graceful handling of failures
- **Scale Confidence**: Add consumers without manual intervention

## 📖 Additional Resources

### Documentation
- [AWS Redshift Serverless Guide](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless.html)
- [Data Sharing Documentation](https://docs.aws.amazon.com/redshift/latest/dg/datashare.html)
- [Network Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)

### Related Files
- [Data Sharing Setup Guide](scripts/setup/README.md)
- [Test Instance README](test-instance/README.md)
- [Backend Setup Guide](backend-setup/README.md)
- [Main Project README](../../README.md)

## 🤝 Contributing

Contributions welcome! Please test changes in development environment before submitting PRs.