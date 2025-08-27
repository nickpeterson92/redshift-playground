# Redshift Test Drive Setup

This Terraform configuration sets up the infrastructure needed for AWS Redshift Test Drive, which allows you to extract workloads from audit logs and replay them on different clusters for testing and validation.

## Prerequisites

1. **Traditional Deployment**: The traditional Redshift deployment must be running with:
   - Audit logging enabled (connection, user, and user activity logs)
   - Producer and consumer clusters deployed
   - Data sharing configured between clusters

2. **Bootstrap Infrastructure**: VPC and networking from bootstrap deployment

3. **Audit Logs**: Workload data must exist in S3 audit logs from running load tests

4. **Configuration Alignment**: Update `terraform.tfvars` to match your traditional deployment:
   - `database_name` - Must match traditional deployment (default: mydb)
   - `master_username` - Must match traditional deployment (default: admin)
   - `master_password` - Must match traditional deployment (required)
   - `allowed_ip` - Your IP for SSH access (should match other deployments)

## Architecture

```
┌────────────────────────────────────────────────────────┐
│                    Test Drive EC2 Instance             │
│  - m5.8xlarge (prod) or t3.large (dev)                 │
│  - Redshift Test Drive software                        │
│  - Extract and replay tools                            │
└────────────┬────────────────────────┬──────────────────┘
             │                        │
             ▼                        ▼
    ┌────────────────┐       ┌──────────────────┐
    │  S3 Audit Logs │       │ S3 Workload Store│
    │ (from clusters)│       │  (extracted data)│
    └────────────────┘       └──────────────────┘
             │                        │
             ▼                        ▼
    ┌────────────────────────────────────────────┐
    │           Redshift Clusters                │
    │  - Producer (source)                       │
    │  - Sales Consumer (replay target)          │
    │  - Operations Consumer (replay target)     │
    └────────────────────────────────────────────┘
```

## Deployment

1. **Configure and deploy the Test Drive infrastructure**:
   ```bash
   cd redshift-migration/golden-architecture/test-drive
   
   # Review and update terraform.tfvars to match your traditional deployment
   vi terraform.tfvars
   
   terraform init
   terraform plan
   terraform apply
   ```

2. **Wait for EC2 instance to initialize** (5-10 minutes):
   ```bash
   # Get instance IP
   terraform output test_drive_instance_public_ip
   
   # Check user data completion
   ssh -i <your-key> ec2-user@<instance-ip>
   tail -f /var/log/user-data.log
   ```

3. **SSH into the instance**:
   ```bash
   ssh -i <your-key> ec2-user@<instance-ip>
   ```

## Usage

### 1. Extract Workload from Audit Logs

```bash
# Switch to test drive user
sudo su - testdrive

# Extract last 24 hours of workload (default)
/opt/redshift-test-drive/extract-workload.sh

# Or specify custom time range
/opt/redshift-test-drive/extract-workload.sh "2024-01-01 00:00:00" "2024-01-02 00:00:00"
```

The extraction process will:
- Read audit logs from S3
- Parse SQL statements and timing information
- Create a replayable workload file
- Upload to S3 workload bucket

### 2. Replay Workload on Consumer Clusters

```bash
# Replay on Sales Consumer
/opt/redshift-test-drive/replay-workload.sh sales

# Replay on Operations Consumer
/opt/redshift-test-drive/replay-workload.sh ops
```

The replay process will:
- Download workload from S3
- Execute SQL statements with original timing
- Maintain concurrency patterns
- Generate performance metrics

### 3. Monitor and Analyze Results

Results are stored in S3:
- Workload files: `s3://<workload-bucket>/workloads/`
- Replay output: `s3://<workload-bucket>/replay-output/[sales|ops]/`

## Configuration Files

Configuration files are located in `/opt/redshift-test-drive/config/`:

- `extract.yaml` - Extraction configuration
- `replay-sales.yaml` - Sales consumer replay configuration
- `replay-ops.yaml` - Operations consumer replay configuration

### Modifying Configuration

```bash
# Edit extraction settings
sudo vi /opt/redshift-test-drive/config/extract.yaml

# Edit replay settings
sudo vi /opt/redshift-test-drive/config/replay-sales.yaml
```

## Advanced Usage

### Custom Python Scripts

The Test Drive repository is cloned to `/opt/redshift-test-drive/repo/`. You can run custom scripts:

```bash
cd /opt/redshift-test-drive/repo/core
source venv/bin/activate
python3 extract.py --help
python3 replay.py --help
```

### Analyzing Performance

```python
# Connect to instance and analyze
cd /opt/redshift-test-drive
python3
```

```python
import boto3
import pandas as pd

# Read replay results from S3
s3 = boto3.client('s3')
# Analysis code here
```

## Troubleshooting

### Connection Issues

1. **Check security groups**: Ensure Redshift clusters allow connections from Test Drive instance
2. **Verify credentials**: Check password in `/opt/redshift-test-drive/config/*.yaml`
3. **Test connectivity**:
   ```bash
   psql -h <cluster-endpoint> -p 5439 -U admin -d mydb -c "SELECT 1"
   ```

### Extraction Issues

1. **Check audit logs exist**: 
   ```bash
   aws s3 ls s3://<audit-bucket>/
   ```

2. **Verify IAM permissions**: Instance role must have S3 read access to audit bucket

3. **Check time range**: Ensure workload exists for specified time period

### Replay Issues

1. **Check workload files**:
   ```bash
   aws s3 ls s3://<workload-bucket>/workloads/
   ```

2. **Verify target cluster**: Ensure consumer clusters are running and accessible

3. **Review logs**:
   ```bash
   tail -f /opt/redshift-test-drive/logs/*.log
   ```

## Cost Optimization

- Use `t3.large` for development/testing
- Use `m5.8xlarge` for production workloads
- Stop instance when not in use:
  ```bash
  aws ec2 stop-instances --instance-ids $(terraform output -raw test_drive_instance_id)
  ```

## Cleanup

```bash
terraform destroy
```

This will remove:
- EC2 instance
- S3 workload bucket
- IAM roles and policies
- Security groups
- CloudWatch logs

## Security Considerations

1. **Network Security**: 
   - Instance is in public subnet with restricted SSH access
   - Redshift connections use private IPs within VPC

2. **Credentials**:
   - Passwords are stored in configuration files
   - Consider using AWS Secrets Manager for production

3. **IAM Permissions**:
   - Instance role has minimal required permissions
   - S3 access limited to specific buckets

## Next Steps

1. **Generate workload**: Run load tests to create audit logs
2. **Extract and replay**: Test workload replay on consumers
3. **Analyze performance**: Compare metrics between clusters
4. **Optimize**: Tune consumer configurations based on results