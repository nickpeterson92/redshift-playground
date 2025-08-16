# Redshift Serverless Data Sharing with Network Load Balancer

🚀 **Production-ready standalone deployment** of AWS Redshift Serverless featuring:
- Self-contained infrastructure (creates own VPC)
- Horizontal scaling through Network Load Balancer (NLB)
- Data sharing patterns with read/write separation
- Comprehensive monitoring and diagnostic tools

## 🎯 Architecture Goals

1. **Separation of Concerns**: Producer handles writes, consumers handle reads
2. **Horizontal Scaling**: Add more consumers as read demand grows
3. **High Availability**: Multiple consumers provide redundancy
4. **Cost Efficiency**: Serverless model with auto-scaling and auto-pause
5. **Load Distribution**: NLB intelligently distributes queries across healthy consumers
6. **Zero Data Movement**: Data sharing without copying or ETL
7. **Independent Scaling**: Each workgroup scales based on its workload

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

Note: Producer handles writes directly. NLB distributes read queries across identical consumers.
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
    ├── get-endpoint-ips.sh    # Extract VPC endpoints
    └── test-nlb.sh            # NLB connectivity test
```

## ✨ Key Features

### Core Capabilities
- **Modular Terraform Design**: Reusable modules for all components
- **Multi-Environment Support**: Separate configurations for dev/staging/prod
- **Comprehensive Security**: KMS encryption, IAM roles, security groups, VPC isolation
- **Horizontal Scalability**: Add consumers on-demand without downtime
- **Cost Optimization**: Auto-pause, right-sizing, and workload isolation

### Advanced Features (Tested)
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
# - Set a secure password
# - Keep create_vpc = true (default)
```

### 3. Deploy Infrastructure

```bash
# Update backend.tf with values from step 1
vim backend.tf  # Add bucket and dynamodb_table values

# Initialize Terraform
terraform init

# Deploy everything
terraform apply
```

**Note**: This creates its own VPC by default. No need for traditional deployment!

### 5. Set Up Data Sharing

After deployment, Terraform will output the exact SQL commands to run:

```bash
terraform output data_sharing_commands
```

Execute these commands in order:
1. On Producer: Create datashare and grant permissions
2. On Consumer(s): Create database from datashare
3. Verify: Query shared tables from consumers

### 6. (Optional) Deploy NLB for Load Balancing

To add Network Load Balancer for horizontal scaling:

```hcl
# In main.tf, add:
module "nlb" {
  source = "./modules/nlb"
  
  vpc_id                = module.networking.vpc_id
  subnet_ids            = module.networking.private_subnet_ids
  consumer_endpoint_ids = [module.consumer_analytics.endpoint_id]
  
  tags = var.tags
}
```

### 7. Monitor Deployment (NEW! 🎉)

```bash
# Option 1: Deploy with integrated monitoring (recommended)
./scripts/deploy-with-monitor.sh

# Option 2: Run monitor separately in another terminal
terraform apply              # Terminal 1
./scripts/deploy-monitor.sh  # Terminal 2

# Features:
# - Real-time EKG heartbeat animation
# - Lock status tracking
# - Workgroup creation progress
# - Success fireworks 🎆 or failure explosion 💥
# - Automatic phase detection
```

### 8. Test NLB Connectivity

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

**When to use existing VPC**:
- Integrating with existing infrastructure
- Corporate networking requirements
- Shared services VPC

**Requirements for existing VPC**:
- Must have subnets in 3+ availability zones
- Each subnet needs 32+ available IPs
- DNS hostnames and DNS resolution enabled

## 📦 Module Details

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
  - Creates and manages datashares
  - Grants access to consumer namespaces

### Consumer Module
- **Serverless Workgroups**:
  - Configurable base/max RPU capacity
  - Workload-specific sizing (analytics vs reporting)
  - Auto-pause configuration
- **VPC Endpoints**:
  - Automatic endpoint creation
  - IP address management for NLB targets
  - DNS resolution for private access
- **Performance**:
  - Query timeout settings
  - Workload management queues
  - Result caching configuration

### NLB Module (New)
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

## 📋 Best Practices

1. **Credentials**: Use AWS Secrets Manager or SSM Parameter Store
2. **Networking**: Keep producer in private subnet
3. **Monitoring**: Set up CloudWatch alarms
4. **Backup**: Configure snapshot policies
5. **Access**: Use IAM authentication when possible

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
- **Analytics (32 RPU, 4hr/day)**: ~$138
- **Reporting (32 RPU, 2hr/day)**: ~$69
- **Total**: ~$483/month

## 🔍 Troubleshooting

### Monitoring Tools

We provide diagnostic scripts to help identify issues during deployment:

#### Real-time Deployment Monitor
```bash
# Monitor all workgroups during deployment
./scripts/monitor-deployment.sh

# Custom refresh interval (default 10 seconds)
./scripts/monitor-deployment.sh 5
```

Shows:
- Current status of all workgroups and namespaces
- VPC endpoint states
- Subnet IP availability warnings
- Recent CloudTrail events
- Elapsed time and timeout warnings

#### Workgroup Diagnostics
```bash
# Diagnose all workgroups
./scripts/diagnose-workgroup.sh

# Diagnose specific workgroup
./scripts/diagnose-workgroup.sh airline-consumer-1
```

Checks:
- Workgroup and namespace status
- VPC endpoint configuration
- Subnet IP availability
- Resource limits and RPU allocation
- Time stuck in MODIFYING state

### Common Issues & Solutions

1. **Subnet Configuration Errors**
   - **Error**: "Subnets must span at least 3 AZs"
   - **Solution**: Ensure you have subnets in 3 different availability zones
   - **Prevention**: Use /23 CIDR blocks for adequate IP space

2. **Namespace Not Found**
   - **Error**: "Namespace does not exist"
   - **Solution**: Wait 2-3 minutes for namespace creation
   - **Verification**: Check AWS Console for namespace status

3. **Access Denied on Data Sharing**
   - **Error**: "Permission denied to access datashare"
   - **Solution**: Run `ALTER DATASHARE SET PUBLICACCESSIBLE TRUE`
   - **Check**: Verify consumer namespace ID matches

4. **NLB Target Unhealthy**
   - **Error**: Target health check failing
   - **Solution**: Verify security group allows port 5439
   - **Debug**: Check VPC endpoint is active and has IPs

5. **Connection Timeout via NLB**
   - **Error**: Connection timed out
   - **Solution**: Ensure NLB security group allows your IP
   - **Test**: Use test-instance scripts to validate

6. **Workgroup Stuck in MODIFYING State**
   - **Common Causes**:
     - Subnet IP exhaustion (need ~32 IPs per workgroup)
     - Another workgroup operation in progress
     - AWS service delays (can take 15-20 minutes)
     - VPC endpoint creation delays
   - **Diagnosis**:
     ```bash
     # Check workgroup status and details
     ./scripts/diagnose-workgroup.sh <workgroup-name>
     
     # Monitor in real-time
     ./scripts/monitor-deployment.sh
     ```
   - **Solutions**:
     1. **Wait**: AWS can be slow, wait 15-20 minutes
     2. **Check IPs**: Verify subnet has >32 available IPs
     3. **Check Limits**: Ensure not hitting account limits
     4. **Sequential Creation**: Module now enforces sequential creation
     5. **Last Resort**: Delete and recreate if stuck >30 minutes
   - **Prevention**:
     - Use /23 subnets (512 IPs) minimum
     - Deploy consumers sequentially (built into module)
     - Monitor during deployment
     - Check AWS service health dashboard

### Atomic Locking Mechanism for Sequential Workgroup Creation

This deployment uses an innovative atomic locking mechanism to prevent AWS API race conditions when creating multiple Redshift Serverless workgroups. This solves a critical issue where concurrent workgroup creation causes workgroups to get stuck in "MODIFYING" state.

#### The Problem
- AWS Redshift Serverless API can't handle multiple simultaneous workgroup creation requests
- Terraform's `count` parameter creates resources in parallel by default
- Concurrent creation leads to workgroups stuck in "MODIFYING" state indefinitely
- Traditional file-based locks have race conditions (multiple processes can check and create simultaneously)

#### The Solution: Atomic Directory-Based Locking
Our modules use `mkdir` as an atomic operation - only one process can successfully create a directory:

```bash
# Location of the lock directory
/tmp/redshift-consumer-lock.d/lock/

# Lock contents
owner       # Process ID and namespace that holds the lock
workgroup   # Name of workgroup being created
timestamp   # When lock was acquired (for stale lock detection)
```

#### How It Works

1. **Lock Acquisition** (sequential_create.sh):
   ```bash
   # Try to create lock directory atomically
   if mkdir "$LOCK_FILE" 2>/dev/null; then
       # Success! We have the lock
       echo "$my_id" > "$LOCK_FILE/owner"
   else
       # Failed - another process has the lock, wait
   fi
   ```

2. **Creation Sequence**:
   - Producer module acquires lock → creates workgroup → waits for AVAILABLE → releases lock
   - Consumer 1 acquires lock → creates workgroup → waits for AVAILABLE → releases lock
   - Consumer 2 acquires lock → creates workgroup → waits for AVAILABLE → releases lock
   - And so on...

3. **Stale Lock Detection**:
   - Checks timestamp to detect locks older than 10 minutes
   - Queries AWS to see if the locking workgroup is actually AVAILABLE
   - Automatically cleans up stale locks

4. **Wait Script** (wait_for_workgroup.sh):
   - Polls AWS API until workgroup status is "AVAILABLE"
   - Handles AWS API propagation delays gracefully
   - Only releases lock after workgroup is fully ready

#### Benefits
- **No Race Conditions**: `mkdir` is atomic at the OS level
- **Self-Healing**: Automatic stale lock cleanup
- **Minimal Overhead**: Next workgroup starts immediately after previous completes
- **Terraform Native**: Works seamlessly with Terraform's lifecycle
- **Debugging Friendly**: Lock files contain diagnostic information

#### Scaling Considerations
- Adding consumers via `consumer_count` in tfvars automatically uses this mechanism
- Each new consumer waits its turn, preventing API conflicts
- Typical creation time: 2-3 minutes per workgroup
- Total time for N consumers: ~3N minutes (sequential, not parallel)

### Monitoring Scripts

```bash
# Full deployment monitor with EKG heartbeat and progress tracking
./scripts/deploy-monitor.sh

# Deploy with integrated monitoring (splits terminal with tmux if available)
./scripts/deploy-with-monitor.sh

# Original workgroup status monitor
./scripts/monitor-deployment.sh

# Diagnose stuck workgroups
./scripts/diagnose-workgroup.sh <workgroup-name>
```

### Useful Commands

```bash
# Monitor lock status during deployment
ls -la /tmp/redshift-consumer-lock.d/lock/

# Check which workgroup holds the lock
cat /tmp/redshift-consumer-lock.d/lock/owner

# Manually clean up lock if needed (use with caution!)
rm -rf /tmp/redshift-consumer-lock.d/lock

# Check deployment status
terraform show

# Destroy specific module
terraform destroy -target=module.consumer_reporting

# Import existing resources
terraform import module.producer.aws_redshift_cluster.producer my-existing-cluster

# Force recreation of stuck workgroup
terraform taint module.consumer_3.aws_redshiftserverless_workgroup.consumer
terraform apply

# Check workgroup status via AWS CLI
aws redshiftserverless list-workgroups --query 'workgroups[*].[workgroupName,status]' --output table

# Get detailed workgroup info
aws redshiftserverless get-workgroup --workgroup-name <name> --query 'workgroup.{Status:status,Created:createdAt,Endpoint:endpoint.address}'
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

### Enterprise Features
6. **Cost Management**:
   - Implement tagging strategy
   - Set up cost allocation reports
   - Configure budget alerts

7. **Integration**:
   - Connect to AWS Lake Formation
   - Integrate with AWS Glue catalog
   - Set up federated queries

## 📚 Lessons Learned from NLB Testing

### Successful Implementations
1. **VPC Endpoint Discovery**:
   - VPC endpoints create multiple ENIs with private IPs
   - These IPs can be registered as NLB targets
   - Health checks validate Redshift availability

2. **Load Distribution**:
   - NLB successfully distributes connections
   - Sticky sessions not required for Redshift
   - Connection pooling works as expected

3. **High Availability**:
   - Failed consumers automatically removed from rotation
   - New consumers can be added without downtime
   - Zero-downtime updates possible

### Technical Insights
4. **Network Configuration**:
   - Security groups must allow health check traffic
   - Cross-zone load balancing recommended
   - Connection draining prevents query interruption

5. **Testing Methodology**:
   - EC2 instances effective for connection testing
   - psql client sufficient for validation
   - Load testing scripts help verify distribution

## 📖 Additional Resources

### Documentation
- [AWS Redshift Serverless Guide](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless.html)
- [Data Sharing Documentation](https://docs.aws.amazon.com/redshift/latest/dg/datashare.html)
- [Network Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)

### Related Files
- [Test Instance README](test-instance/README.md)
- [Backend Setup Guide](backend-setup/README.md)
- [Main Project README](../../README.md)

## 🤝 Contributing

Contributions welcome! Please test changes in development environment before submitting PRs.