# AWS Redshift Migration Playground

A comprehensive playground for exploring AWS Redshift deployment patterns, data sharing, and horizontal scaling architectures.

## 🎯 Overview

This repository provides production-ready Terraform modules and deployment patterns for:
- Traditional Redshift clusters
- Modern Redshift Serverless with data sharing
- Horizontal scaling using Network Load Balancers
- Multi-consumer read replica patterns

## 📁 Project Structure

```
redshift-migration/
├── traditional/          # Traditional provisioned Redshift cluster
│   └── README.md        # Detailed setup and configuration
│
├── data-sharing/        # Redshift Serverless with NLB and data sharing
│   ├── README.md        # Complete deployment guide
│   ├── modules/         # Reusable Terraform modules
│   ├── environments/    # Environment configurations (dev/staging/prod)
│   ├── test-instance/   # EC2-based testing infrastructure
│   └── scripts/         # Monitoring and utility scripts
│
└── data-generation/     # Sample data generation utilities
    └── README.md        # Data generation guide
```

## 🚀 Quick Start

### For Redshift Serverless with Data Sharing (Recommended)

```bash
cd data-sharing
# Follow the comprehensive guide in data-sharing/README.md
```

This deployment includes:
- ✅ Self-contained VPC infrastructure
- ✅ Producer namespace for writes
- ✅ Multiple consumer workgroups for reads
- ✅ Network Load Balancer for query distribution
- ✅ Visual deployment monitoring
- ✅ Cost optimization with auto-pause

### For Traditional Redshift Cluster

```bash
cd traditional
# Follow the guide in traditional/README.md
```

## 🏗️ Architecture Patterns

### Pattern 1: Data Sharing with Horizontal Scaling
```
Producer (Writes) → Data Sharing → Consumers (Reads) → NLB → Applications
```
**Use Case**: High-concurrency read workloads with workload isolation

### Pattern 2: Traditional Single Cluster
```
Applications → Redshift Cluster → All Workloads
```
**Use Case**: Simple deployments with predictable workloads

## 📊 Sample Data

The repository includes scripts to generate a sample airline data warehouse with:
- Dimension tables (aircraft, airports, customers, dates, flights)
- Fact tables (bookings, flight operations)
- ~1GB of sample data for testing

See `data-generation/README.md` for details.

## 🔧 Key Technologies

- **Terraform**: Infrastructure as Code
- **AWS Redshift Serverless**: Modern serverless data warehouse
- **Network Load Balancer**: Layer 4 load distribution
- **Python**: Monitoring and data generation scripts
- **PostgreSQL**: Client tools and SQL scripts

## 📚 Documentation

Each subdirectory contains detailed documentation:
- [`data-sharing/README.md`](data-sharing/README.md) - Complete Serverless deployment guide
- [`data-sharing/test-instance/README.md`](data-sharing/test-instance/README.md) - NLB testing guide
- [`data-sharing/environments/README.md`](data-sharing/environments/README.md) - Multi-environment setup
- [`traditional/README.md`](traditional/README.md) - Traditional cluster deployment

## 🔒 Security Notes

- Never commit passwords or secrets to version control
- Use AWS Secrets Manager for production deployments
- Follow least-privilege IAM policies
- Enable encryption at rest and in transit
- Use VPC endpoints for private connectivity

## 💰 Cost Considerations

**Redshift Serverless**:
- Pay only for active RPU-hours
- Auto-pause when idle
- Scale from 32 to 512 RPUs

**Traditional Clusters**:
- Pay for provisioned nodes 24/7
- Reserved instances for cost savings
- Manual pause/resume required

## 🤝 Contributing

This is a learning playground - feel free to experiment and share improvements!

## 📝 License

Personal learning project - use at your own risk.

## 🔗 Resources

- [AWS Redshift Documentation](https://docs.aws.amazon.com/redshift/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Redshift Data Sharing Guide](https://docs.aws.amazon.com/redshift/latest/dg/datashare.html)