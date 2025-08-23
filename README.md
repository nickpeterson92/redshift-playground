# Redshift Playground

AWS Redshift learning playground with Terraform Infrastructure as Code.

## 📁 What's Inside

```
redshift-playground/
└── redshift-migration/
    ├── golden-architecture/        # ⭐ Main: Serverless with NLB & data sharing
    ├── traditional/                # Legacy: Traditional cluster deployment
    ├── monitoring/                 # Python+Curses monitoring TUI utils
    └── data-generation/            # Sample airline data generator
```

## 🚀 Quick Start

```bash
cd redshift-migration/golden-architecture
# See README.md for complete setup instructions
```

## 🏗️ Architecture

**Data Sharing Pattern**: Producer (writes) → Data Share → Consumers (reads) → NLB → Applications

- **Producer**: Handles all write operations (ETL, updates)
- **Consumers**: Read-only access via data sharing
- **NLB**: Distributes read queries across multiple consumers
- **Auto-scaling**: Each workgroup scales independently (32-512 RPUs)

## 📚 Documentation

- [Data Sharing Setup](redshift-migration/data-sharing/README.md) - Complete deployment guide
- [Redshift Migration](redshift-migration/README.md) - Project overview
- [Test Infrastructure](redshift-migration/data-sharing/test-instance/README.md) - NLB testing

## 🔧 Technologies

- Terraform
- AWS Redshift Serverless
- Network Load Balancer
- Python (monitoring & data generation)

## 📝 License

Personal learning project - use at your own risk.