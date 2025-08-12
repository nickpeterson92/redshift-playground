# Redshift Migration Project

This project demonstrates a complete migration from traditional Redshift cluster to Redshift Serverless using realistic airline data.

## Project Structure

```
redshift-migration/
├── traditional/          # Traditional Redshift cluster deployment
│   ├── redshift.tf      # Cluster infrastructure
│   └── terraform.tfvars # Configuration values
├── serverless/          # Redshift Serverless deployment
│   ├── redshift-serverless.tf
│   └── terraform.tfvars # Configuration values
├── shared/              # Shared resources (VPC, S3, etc.)
├── data-generation/     # Mock airline data generation
│   ├── redshift-airline-schema.sql
│   └── generate-airline-data.py
├── migration-scripts/   # Migration utilities and scripts
├── docs/               # Documentation
│   ├── connection-guide.md
│   └── README_REDSHIFT.md
└── README.md           # This file
```

## Architecture Overview

### Traditional Cluster (Current State)
- Single-node ra3.xlplus cluster
- Fixed capacity (24/7 billing)
- ~$414/month regardless of usage
- Manual scaling required

### Serverless (Target State)
- Auto-scaling from 32-128 RPUs
- Pay-per-use billing
- ~$11.52/hour when active (minimum)
- Automatic pause when idle

## Migration Path

### Phase 1: Setup Infrastructure ✓
- Traditional cluster deployment
- Mock airline data generation
- Serverless infrastructure setup

### Phase 2: Data Loading (Current)
- Load airline data into traditional cluster
- Establish baseline performance metrics
- Document query patterns

### Phase 3: Migration Execution
- Use AWS DMS or UNLOAD/COPY
- Parallel testing
- Performance validation

### Phase 4: Optimization
- Implement best practices
- Auto-scaling configuration
- Cost optimization

## Golden Architecture Patterns

### 1. Data Organization
- **Distribution Keys**: High-cardinality columns (customer_key, date_key)
- **Sort Keys**: Query predicates (date ranges, airport codes)
- **Compression**: Automatic encoding for columns

### 2. Schema Design
- **Star Schema**: Optimized for analytics
- **Materialized Views**: For common aggregations
- **Late Binding Views**: For schema flexibility

### 3. Performance Optimization
- **Workload Management**: Query priorities and queues
- **Result Caching**: Automatic in Serverless
- **Concurrency Scaling**: Elastic compute for bursts

### 4. Cost Optimization
- **Auto-pause**: Serverless pauses after inactivity
- **RPU Sizing**: Start small (32), scale as needed
- **Data Lifecycle**: Archive old data to S3

## Quick Start

### 1. Deploy Traditional Cluster
```bash
cd traditional
terraform init
terraform apply
```

### 2. Deploy Serverless
```bash
cd ../serverless
terraform init
terraform apply
```

### 3. Load Data
```bash
cd ../data-generation
# Update connection details in generate-airline-data.py
python generate-airline-data.py
```

### 4. Run Migration
See migration-scripts/ for detailed steps

## Key Learnings

1. **Serverless Benefits**
   - No idle costs
   - Automatic scaling
   - Built-in HA

2. **Migration Considerations**
   - Network transfer costs
   - Downtime planning
   - Query compatibility

3. **Best Practices**
   - Test with production-like workloads
   - Monitor performance metrics
   - Implement gradual cutover