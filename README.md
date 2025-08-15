# Redshift Migration & Data Sharing Architecture

A comprehensive AWS Redshift implementation showcasing migration strategies, serverless architectures, data sharing patterns, and advanced networking configurations with Network Load Balancer (NLB) for horizontal scaling.

## 🚀 Project Overview

This project demonstrates:
- **Primary**: Production-grade Redshift Serverless with data sharing
- **Optional**: Traditional Redshift cluster for initial data loading
- Horizontal scaling using Network Load Balancer (NLB)
- Read/write separation with producer/consumer pattern
- Cost optimization with auto-pause and right-sizing
- Real-world airline data model with star schema design

## Project Structure

```
redshift-playground/
├── README.md                # This file
└── redshift-migration/
    ├── data-sharing/        # 🎯 PRIMARY: Production serverless architecture
    │   ├── main.tf          # Root module orchestration
    │   ├── variables.tf     # Input variables
    │   ├── outputs.tf       # Data sharing commands
    │   ├── terraform.tfvars.example # Example configuration
    │   └── modules/         # Terraform modules
    ├── traditional/         # 💾 OPTIONAL: For initial data loading only
    │   ├── redshift.tf      # Traditional cluster + VPC
    │   ├── README.md        # When/why you might need this
    │   └── terraform.tfvars.example
    ├── serverless/          # 📦 DEPRECATED: Use data-sharing instead
    │   ├── modules/         # Terraform modules
    │   │   ├── producer/    # Write-optimized namespace
    │   │   ├── consumer/    # Read-optimized workgroups
    │   │   ├── networking/  # VPC, subnets, security
    │   │   ├── nlb/        # Network Load Balancer module
    │   │   └── backend/     # State management
    │   ├── backend-setup/   # Remote state infrastructure
    │   ├── environments/    # Environment configurations
    │   │   └── dev/        # Development environment
    │   ├── test-instance/   # NLB testing infrastructure
    │   │   ├── main.tf     # EC2 test instances
    │   │   └── test-*.sh   # Testing scripts
    │   ├── scripts/         # Utility scripts
    │   ├── main.tf          # Root module orchestration
    │   ├── variables.tf     # Input variables
    │   └── outputs.tf       # Data sharing commands
    ├── data-generation/     # Mock airline data
    │   ├── redshift-airline-schema-fixed.sql
    │   ├── generate-airline-data-simple.py
    │   └── setup-schemas.py
    └── docs/                # Extended documentation
        ├── connection-guide.md
        ├── golden-architecture-patterns.md
        └── migration-strategy.md
```

## Architecture Overview

### Production Architecture (Implemented)

#### Basic Data Sharing Architecture
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
        ┌───────▼────────┐      ┌─────────▼────────┐
        │   Analytics    │      │    Reporting     │
        │   Consumer     │      │    Consumer      │
        │   (Read Only)  │      │    (Read Only)   │
        └────────────────┘      └──────────────────┘
```

#### Advanced NLB Architecture (Horizontal Scaling)
```
     ETL/Writes ───┐
                   ▼
          ┌─────────────────┐
          │   Producer      │
          │  (Serverless)   │
          │  32-256 RPUs    │
          └──────┬─────────┘
                 │ Data Sharing
        ┌────────┼────────┬────────┐
        ▼        ▼        ▼        ▼
   ┌────────┐┌────────┐┌────────┐┌────────┐
   │Consumer││Consumer││Consumer││Consumer│
   │    1   ││   2    ││   3    ││   N    │
   │ 32 RPU ││ 32 RPU ││ 32 RPU ││ 32 RPU │
   └───┬────┘└───┬────┘└───┬────┘└───┬────┘
       └─────────┼─────────┼─────────┘
                 │ VPC Endpoints
          ┌──────▼──────────┐
          │      NLB        │
          │  Load Balancer  │
          │   Port 5439     │
          └──────┬──────────┘
                 │ Read Queries
          ┌──────▼─────────┐
          │  Applications  │
          │   & BI Tools   │
          └────────────────┘

Note: Producer handles writes directly. NLB only distributes read queries.
```

### Key Components

1. **Producer Namespace** (Write Operations)
   - Serverless: 32-256 RPUs
   - Handles all write operations (ETL, inserts, updates)
   - Owns the source data
   - Manages data sharing permissions

2. **Consumer Namespaces** (Read Operations)
   **Option A: Workload-Specific (Without NLB)**
   - Analytics: 32-128 RPUs for complex queries
   - Reporting: 32-64 RPUs for dashboards
   - Each consumer sized for specific workload
   
   **Option B: Identical Pool (With NLB)**
   - All consumers: Same RPU configuration (e.g., 32-64)
   - Load balancer distributes queries evenly
   - Scale horizontally by adding identical consumers

3. **Data Sharing Benefits**
   - No data movement or copying
   - Real-time data access
   - Independent scaling of read/write workloads
   - Cost isolation between teams/workloads

## 🎯 Implementation Status

### ✅ Phase 1: Serverless Architecture
- Standalone data sharing deployment with VPC creation
- Producer namespace for write operations
- Multiple identical consumers for read scaling
- Remote state management with S3/DynamoDB

### ✅ Phase 2: Advanced Features
- Network Load Balancer for horizontal scaling
- Diagnostic tools for monitoring deployments
- Sequential workgroup creation to prevent conflicts
- VPC endpoint support for private connectivity

### ✅ Phase 3: Production Readiness
- Data sharing across namespaces
- Auto-pause for cost optimization
- Health monitoring and diagnostics
- Comprehensive troubleshooting tools

## Quick Start Guide

### Prerequisites
- AWS account with appropriate permissions
- Terraform >= 1.0
- AWS CLI configured
- Python 3.x with psycopg2-binary (only if loading new data)

### Option A: Fresh Deployment (Recommended)

#### 1. Deploy Backend Infrastructure
```bash
cd redshift-migration/data-sharing/backend-setup
terraform init
terraform apply
# Note the output values for backend configuration
```

#### 2. Deploy Data Sharing Architecture
```bash
cd ../
# Copy and update terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your IP and password

# Update backend.tf with values from step 1
terraform init
terraform apply
```

#### 3. Restore Existing Snapshot (If Available)
```bash
# If you have a snapshot with data:
# AWS Console → Redshift Serverless → Producer namespace → Restore from snapshot
```

#### 4. Setup Data Sharing
```bash
# Run the SQL commands from terraform output
terraform output data_sharing_commands
```

### Option B: With Initial Data Loading (Traditional)

**Only needed if you don't have a snapshot and need to create sample data**

#### 1. Deploy Traditional Cluster
```bash
cd redshift-migration/traditional
terraform init
terraform apply -var="master_password=YourPassword123!"
```

#### 2. Load Sample Data
```bash
cd ../data-generation
python generate-airline-data-simple.py
```

#### 3. Create Snapshot & Destroy Cluster
```bash
aws redshift create-cluster-snapshot \
  --cluster-identifier my-redshift-cluster \
  --snapshot-identifier airline-data-snapshot

# Destroy traditional cluster to save costs
cd ../traditional
terraform destroy
```

#### 4. Continue with Option A from step 1

## 🔑 Key Features & Innovations

### Data Model - Airline Star Schema
- **Fact Tables**: 
  - `flight_operations` - Operational metrics (delays, cancellations)
  - `bookings` - Revenue and passenger data
  - `daily_revenue` - Aggregated financial metrics
- **Dimension Tables**:
  - `dim_date` - Time dimension with holiday flags
  - `dim_airport` - Location hierarchy (city, state, country)
  - `dim_aircraft` - Fleet information and capacity
  - `dim_customer` - Passenger demographics
  - `dim_flight` - Route and schedule data
- **Optimization**:
  - Strategic DISTKEY on high-cardinality joins
  - Compound SORTKEY for time-series queries
  - Interleaved SORTKEY for multi-dimensional analysis

### Cost Optimization Strategies
- **Serverless Benefits**:
  - Auto-pause when idle (zero cost during inactivity)
  - Per-second billing for actual usage
  - No over-provisioning required
- **Deployment Strategies**:
  - **Without NLB**: Size consumers for specific workloads (analytics: 128 RPU, reporting: 64 RPU)
  - **With NLB**: Use identical smaller consumers (32-64 RPU each) and scale horizontally
- **Development Options**:
  - Traditional cluster: Fixed $414/month for predictable dev costs
  - Serverless dev: Pay-per-use for sporadic testing

### Security & Compliance
- **Network Security**:
  - VPC isolation with private subnets
  - Security groups with least-privilege rules
  - VPC endpoints for AWS service access
- **Access Control**:
  - IAM roles with fine-grained permissions
  - Database user management with group privileges
  - Data sharing with read-only consumer access
- **Data Protection**:
  - KMS encryption at rest
  - SSL/TLS for data in transit
  - Automated snapshot encryption

## 🔧 Troubleshooting Guide

### Common Issues & Solutions

1. **"Publicly accessible consumer" error**
   ```sql
   -- On producer namespace
   ALTER DATASHARE airline_share SET PUBLICACCESSIBLE TRUE;
   ```

2. **Insufficient IP addresses**
   - Ensure subnets are /23 or larger (512 IPs minimum)
   - Require 3 subnets in different AZs
   - Each serverless workgroup needs ~32 IPs

3. **Snapshot restore issues**
   - Verify target namespace exists and is active
   - Check IAM role has `redshift:RestoreFromClusterSnapshot`
   - Ensure KMS key policy allows target namespace

4. **NLB connection issues**
   - Verify target group health checks are passing
   - Check security group allows port 5439
   - Ensure VPC endpoints are configured correctly

5. **Data sharing not visible**
   - Wait 2-3 minutes for propagation
   - Verify consumer namespace ID is correct
   - Check datashare is associated with consumer

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

#### Option A: Workload-Specific (No NLB)
- Producer (32 RPU, 8 hours/day): ~$276/month
- Analytics (64 RPU, 4 hours/day): ~$276/month  
- Reporting (32 RPU, 2 hours/day): ~$69/month
- **Total**: ~$621/month

#### Option B: With NLB (Identical Consumers)
- Producer (32 RPU, 8 hours/day): ~$276/month
- 3x Consumers (32 RPU each, 6 hours/day): ~$621/month
- **Total**: ~$897/month (handles 3x the concurrent queries)

## 📚 Lessons Learned

### Infrastructure
1. **VPC Requirements**: 
   - Redshift Serverless requires 3 AZs minimum
   - Use /23 subnets (512 IPs) to avoid IP exhaustion
   - Plan for ~32 IPs per serverless workgroup

2. **Data Sharing Configuration**:
   - Public workgroups need `PUBLICACCESSIBLE TRUE` on datashares
   - Consumer namespaces must be explicitly granted access
   - Cross-namespace queries work immediately after setup

### Development Best Practices
3. **Data Modeling**:
   - Always include primary keys in fact table inserts
   - Use appropriate distribution keys for join performance
   - Consider sort keys based on query patterns

4. **Terraform Organization**:
   - Use remote state (S3 + DynamoDB) for team collaboration
   - Modular design enables environment-specific configurations
   - Separate backend setup prevents circular dependencies

### Performance & Scaling
5. **NLB Testing Results**:
   - Successfully tested load balancing across identical consumers
   - Round-robin distribution works best with same-sized consumers
   - Health checks ensure only active workgroups receive traffic
   - Connection draining prevents query interruption

6. **Cost Management**:
   - Monitor RPU usage to right-size workgroups
   - Use auto-pause aggressively for dev/test environments
   - Consider reserved capacity for predictable workloads

## 🚀 Next Steps & Roadmap

### Phase 4: Production Readiness
- [ ] Implement automated ETL pipelines to producer
- [ ] Set up CloudWatch monitoring and alerting
- [ ] Configure automated backup policies
- [ ] Implement data lifecycle management

### Phase 5: Advanced Features
- [ ] Add cross-region disaster recovery
- [ ] Implement materialized views for performance
- [ ] Set up query monitoring rules (QMR)
- [ ] Create workload management (WLM) queues

### Phase 6: Enterprise Features
- [ ] Integrate with AWS Lake Formation
- [ ] Implement row-level security (RLS)
- [ ] Add data masking for PII
- [ ] Set up cost allocation tags and chargeback

### Phase 7: Optimization
- [ ] Analyze query patterns for further optimization
- [ ] Implement automatic table maintenance
- [ ] Add query result caching strategies
- [ ] Optimize data distribution strategies

## 📖 Additional Resources

### Documentation
- [Connection Guide](redshift-migration/docs/connection-guide.md) - Detailed connection instructions
- [Architecture Patterns](redshift-migration/docs/golden-architecture-patterns.md) - Best practices
- [Migration Strategy](redshift-migration/docs/migration-strategy.md) - Step-by-step migration
- [Data Sharing README](redshift-migration/data-sharing/README.md) - Detailed data sharing setup

### AWS Resources
- [Redshift Serverless Documentation](https://docs.aws.amazon.com/redshift/latest/mgmt/serverless.html)
- [Data Sharing Guide](https://docs.aws.amazon.com/redshift/latest/dg/datashare.html)
- [Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/best-practices.html)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Test your changes in dev environment
4. Submit a pull request

## 📄 License

This is an educational demonstration project. Use at your own risk in production environments.

## 🙏 Acknowledgments

- AWS Redshift team for excellent documentation
- Terraform community for module patterns
- Contributors and testers