# Redshift NLB Test Instance

EC2-based testing infrastructure for validating NLB load balancing and Redshift connectivity.

## 🎯 Purpose

Since the NLB is internal-only (for security), we need EC2 instances within the VPC to test:
- NLB connectivity and health
- Load distribution across consumers  
- Session stickiness behavior
- Data sharing queries through the NLB

## 🏗️ What Gets Deployed

Running `terraform apply` creates:

1. **Two EC2 Instances** (t3.micro)
   - Instance 1: Primary test instance
   - Instance 2: For load balancing verification
   - Both in different subnets for distribution testing

2. **Security Group**
   - SSH access from your IP only
   - Full outbound access for package installation

3. **SSH Key Pair**
   - Auto-generated RSA 4096-bit key
   - Saved locally as `test-instance.pem`

4. **Test Scripts**
   - Automatically copied to both instances
   - Pre-configured with NLB endpoint

## 🚀 Quick Start

### Prerequisites

- Main data-sharing infrastructure deployed
- Your IP address whitelisted in security groups
- AWS credentials configured

### Deploy Test Instances

```bash
cd test-instance

# Initialize (first time only)
terraform init

# Deploy both test instances
terraform apply

# Takes about 2 minutes to fully provision
```

### Run Tests

#### Option 1: Quick Connectivity Test
```bash
export REDSHIFT_PASSWORD='YourActualPassword'  # Use the password from terraform.tfvars
./run-remote-test.sh
```

#### Option 2: Full Test Suite
```bash
# Bash test with multiple queries
./run-remote-test.sh bash

# Python test showing connection distribution
./run-remote-test.sh python
```

#### Option 3: Load Balancing Verification
```bash
# Tests from both instances simultaneously
./test-load-balancing.sh
```

Expected output:
```
Instance 1 → Consumer-1
Instance 2 → Consumer-2
✅ LOAD BALANCING CONFIRMED!
```

## 🧪 Test Scripts

### `run-remote-test.sh`
Main test runner that SSHs into instance and runs tests remotely.

Features:
- Automatic password handling
- Three test modes (quick/bash/python)
- Output appears in your local terminal

### `test-load-balancing.sh`
Verifies NLB distributes connections across consumers.

Tests:
- Different source IPs get different consumers
- Same source IP always hits same consumer (stickiness)
- Both consumers are healthy and serving traffic

### `diagnose.sh`
Troubleshooting script for connectivity issues.

Checks:
- SSH connectivity
- psql installation
- DNS resolution
- Network connectivity
- NLB target health
- Security groups

### `test-nlb-connection.py`
Python script for detailed load distribution analysis.

Shows:
- Connection distribution percentages
- Backend namespace identification
- Session stickiness verification
- Shared data access validation

## 📝 Manual Testing

### SSH to Instance
```bash
ssh -i test-instance.pem ec2-user@$(terraform output -raw instance_public_ip)
```

### Run Queries Directly
```bash
cd redshift-tests
export REDSHIFT_PASSWORD='YourActualPassword'  # Use the password from terraform.tfvars

# Connect through NLB
psql -h <nlb-endpoint> -p 5439 -U admin -d consumer_db

# Query shared data
SELECT * FROM airline_shared.airline_dw.dim_aircraft LIMIT 10;
```

### Check Which Consumer You Hit
```sql
SELECT current_namespace;
```

## 🔧 Troubleshooting

### Connection Timeout
```bash
# Run diagnostics
./diagnose.sh

# Common fixes:
# 1. Check security group allows your IP
# 2. Verify NLB targets are healthy
# 3. Ensure password is correct
```

### NLB Not Reachable
- NLB is internal-only by design
- Must connect from within VPC (EC2 instances)
- Cannot connect directly from your laptop

### Scripts Not Found
```bash
# Re-copy scripts to instance
scp -i test-instance.pem ../test-nlb* ec2-user@<instance-ip>:~/redshift-tests/
```

### Password Issues
- The password must be explicitly set in terraform.tfvars (no default value)
- Passwords must meet AWS requirements (8+ chars, upper, lower, number)
- Reset the password using AWS CLI if needed:
```bash
aws redshift-serverless update-namespace \
  --namespace-name airline-consumer-1 \
  --admin-username admin \
  --admin-user-password 'YourNewPassword123!' # Use a strong password
```

## 🏗️ Infrastructure Details

### Instance Configuration
- **AMI**: Amazon Linux 2023 (latest)
- **Type**: t3.micro (free tier eligible)
- **Storage**: Default EBS
- **Network**: Public IPs for SSH access

### Pre-installed Software
- PostgreSQL 15 client (psql)
- Python 3 with psycopg2
- Basic networking tools

### File Locations
- Test scripts: `/home/ec2-user/redshift-tests/`
- SSH key: `./test-instance.pem`

## 💰 Cost Considerations

- **t3.micro**: ~$0.01/hour per instance
- **EBS storage**: Minimal (8GB default)
- **Data transfer**: Within VPC is free
- **Total**: ~$0.02/hour for both instances

**Remember to destroy when done testing!**

## 🧹 Cleanup

```bash
# Destroy test instances
terraform destroy

# Confirm with 'yes'
```

This removes:
- Both EC2 instances
- Security group
- SSH key pair
- All associated resources

## 📊 Expected Test Results

### Successful Load Balancing
```
Instance 1 → 8cfa12a1-c9e2-48aa-8726-82dcd91e8751 (Consumer-1)
Instance 2 → 638fd081-45d3-4e0e-87e0-ee4d88991377 (Consumer-2)
```

### Session Stickiness
```
Connection 1: ✅ Same consumer
Connection 2: ✅ Same consumer  
Connection 3: ✅ Same consumer
```

### Data Sharing Access
```
Aircraft count: 10
Airport count: 10
Customer count: 1000
```

## 🔗 Integration with Main Infrastructure

The test instances automatically:
1. Read VPC/subnet info from main deployment state
2. Get NLB endpoint from Terraform outputs
3. Use same security credentials
4. Reference remote S3 state (no local state dependencies)

## 📚 Additional Resources

- [EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [NLB Target Health](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/target-group-health-checks.html)
- [psql Documentation](https://www.postgresql.org/docs/current/app-psql.html)