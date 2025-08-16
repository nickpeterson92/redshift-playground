# Data Sharing Setup Scripts

This directory contains scripts for automating Redshift Serverless data sharing configuration.

## Overview

The data sharing setup is now **fully automated** during Terraform deployment. The setup:

1. **Automatically runs** when you deploy infrastructure with `terraform apply`
2. **Intelligently detects** new consumers vs existing ones
3. **Only configures** new consumers, avoiding unnecessary reconfiguration
4. **Handles scaling** seamlessly when you add more consumers

## How It Works

### Automatic Setup During Deployment

When you run `terraform apply`:

1. The `datashare-setup` module is triggered
2. It configures the producer's datashare with all consumer namespace IDs
3. It detects which consumers are new (not yet configured)
4. It only sets up data sharing for new consumers
5. Existing consumers remain untouched

### Scaling Scenarios

#### Adding New Consumers
When you increase `consumer_count`:
```bash
# In terraform.tfvars
consumer_count = 5  # Increased from 3

# Apply changes
terraform apply
```

The automation will:
- Deploy new consumer infrastructure
- Grant the new consumers access to the producer's datashare
- Configure only the new consumers (consumers 4 and 5)
- Leave existing consumers (1-3) unchanged

#### Horizontal Scaling Only
If you're just adding compute capacity without changing data:
- The script detects existing consumers have data sharing configured
- Skips redundant configuration
- Completes quickly without errors

## Manual Execution

While the setup is automated, you can also run it manually if needed:

### Using the Generated Script
```bash
# After terraform apply, a convenience script is created
./scripts/setup/run-setup.sh

# To configure all consumers (including existing ones)
./scripts/setup/run-setup.sh --all-consumers

# To configure only new consumers (default behavior)
./scripts/setup/run-setup.sh --new-consumers-only
```

### Direct Script Execution
```bash
# Get Terraform outputs
terraform output -json > tf_output.json

# Run setup for new consumers only (default)
./scripts/setup/setup-datashare.sh tf_output.json --new-consumers-only

# Run setup for all consumers
./scripts/setup/setup-datashare.sh tf_output.json
```

## Files

- `setup-datashare.sh` - Main automation script
- `02-configure-datashare.sql` - SQL commands for producer setup (reference)
- `03-configure-consumers.sql` - SQL commands for consumer setup (reference)
- `run-setup.sh` - Generated convenience script after `terraform apply`

## Features

### Intelligent Detection
The script checks if a consumer already has the `airline_shared` database configured:
- If yes: Skips configuration
- If no: Sets up data sharing

### Error Handling
- Validates all required parameters
- Checks connectivity before executing
- Provides colored output for easy debugging
- Safe to run multiple times (idempotent)

### Security
- Uses environment variables for sensitive data
- Credentials are passed from Terraform securely
- No hardcoded passwords in scripts

## Troubleshooting

### Data Sharing Not Working
```bash
# Check producer datashare status
psql -h <producer-endpoint> -U <username> -d airline_dw -c "SHOW DATASHARES;"

# Check consumer access
psql -h <consumer-endpoint> -U <username> -d consumer_db -c "SELECT * FROM svv_all_tables WHERE database_name = 'airline_shared';"
```

### Script Fails During Deployment
1. Check AWS credentials and permissions
2. Ensure Redshift Serverless endpoints are accessible
3. Verify security groups allow psql connections (port 5439)
4. Check the Terraform logs for detailed error messages

### Manual Recovery
If automatic setup fails:
```bash
# Run manual setup for all consumers
terraform output -json > tf_output.json
./scripts/setup/setup-datashare.sh tf_output.json
```

## Requirements

- `psql` client installed locally
- `jq` for JSON parsing
- Network access to Redshift Serverless endpoints (port 5439)
- Proper AWS credentials and IAM permissions