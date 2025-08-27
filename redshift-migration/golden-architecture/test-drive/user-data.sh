#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Redshift Test Drive setup at $(date)..."
echo "Instance type: $(ec2-metadata --instance-type | cut -d ' ' -f 2)"

# Update system
yum update -y

# Install required packages
echo "Installing system packages..."
# Enable PostgreSQL on Amazon Linux 2
amazon-linux-extras enable postgresql14
yum clean metadata

yum install -y \
  git \
  python3 \
  python3-pip \
  postgresql \
  gcc \
  gcc-c++ \
  python3-devel \
  openssl-devel \
  cyrus-sasl-devel

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws

# Create test drive user and directories
echo "Setting up test drive user and directories..."
useradd -m -s /bin/bash testdrive || true
mkdir -p /opt/redshift-test-drive
mkdir -p /opt/redshift-test-drive/workloads
mkdir -p /opt/redshift-test-drive/logs
mkdir -p /opt/redshift-test-drive/output
mkdir -p /opt/redshift-test-drive/config

# Clone Redshift Test Drive repository
echo "Cloning Redshift Test Drive repository..."
cd /opt/redshift-test-drive
git clone https://github.com/aws/redshift-test-drive.git repo

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install --upgrade pip
pip3 install \
  psycopg2-binary \
  boto3 \
  pyyaml \
  pandas \
  numpy \
  pytz \
  python-dateutil \
  cryptography \
  urllib3 \
  requests

# ODBC driver installation commented out - not required for Python scripts
# The Test Drive uses psycopg2 for database connections, not ODBC
echo "Skipping ODBC driver installation (not required for Python-based Test Drive)..."

# # Install ODBC driver for Redshift (if needed in future)
# echo "Installing Redshift ODBC driver..."
# # Try the latest version of the ODBC driver
# wget https://s3.amazonaws.com/redshift-downloads/drivers/odbc/2.1.3.0/AmazonRedshiftODBC-64-bit-2.1.3.0-1.x86_64.rpm || \
#   wget https://s3.amazonaws.com/redshift-downloads/drivers/odbc/1.5.16.1016/AmazonRedshiftODBC-64-bit-1.5.16.x86_64.rpm
# yum install -y AmazonRedshiftODBC-*.rpm
# rm -f AmazonRedshiftODBC-*.rpm
# 
# # Configure ODBC
# echo "Configuring ODBC..."
# cat > /etc/odbc.ini << 'EOF'
# [Amazon Redshift]
# Driver = Amazon Redshift (x64)
# EOF
# 
# cat > /etc/odbcinst.ini << 'EOF'
# [Amazon Redshift (x64)]
# Description = Amazon Redshift ODBC Driver (64-bit)
# Driver = /opt/amazon/redshiftodbc/lib/64/libamazonredshiftodbc64.so
# EOF

# Create configuration files
echo "Creating configuration files..."

# Extract configuration
cat > /opt/redshift-test-drive/config/extract.yaml << EOF
source_cluster_endpoint: "${producer_endpoint}"
database_name: "${redshift_database}"
username: "${redshift_user}"
password: "${redshift_password}"
audit_logs_bucket: "${audit_logs_bucket}"
workload_output_bucket: "${workload_bucket}"
workload_output_prefix: "workloads/"
start_time: "auto"  # Will be set when running
end_time: "auto"    # Will be set when running
log_level: "INFO"
EOF

# Replay configuration for Sales Consumer
cat > /opt/redshift-test-drive/config/replay-sales.yaml << EOF
target_cluster_endpoint: "${consumer_sales_endpoint}"
database_name: "${redshift_database}"
username: "${redshift_user}"
password: "${redshift_password}"
workload_input_bucket: "${workload_bucket}"
workload_input_prefix: "workloads/"
replay_output_bucket: "${workload_bucket}"
replay_output_prefix: "replay-output/sales/"
concurrency: 10
log_level: "INFO"
EOF

# Replay configuration for Operations Consumer
cat > /opt/redshift-test-drive/config/replay-ops.yaml << EOF
target_cluster_endpoint: "${consumer_ops_endpoint}"
database_name: "${redshift_database}"
username: "${redshift_user}"
password: "${redshift_password}"
workload_input_bucket: "${workload_bucket}"
workload_input_prefix: "workloads/"
replay_output_bucket: "${workload_bucket}"
replay_output_prefix: "replay-output/ops/"
concurrency: 10
log_level: "INFO"
EOF

# Create helper scripts
echo "Creating helper scripts..."

# Extract workload script
cat > /opt/redshift-test-drive/extract-workload.sh << 'EOF'
#!/bin/bash
cd /opt/redshift-test-drive/repo/core
source venv/bin/activate 2>/dev/null || {
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
}

# Set time range (last 24 hours by default)
START_TIME=$${1:-$$(date -u -d '24 hours ago' '+%Y-%m-%d %H:%M:%S')}
END_TIME=$${2:-$$(date -u '+%Y-%m-%d %H:%M:%S')}

echo "Extracting workload from $$START_TIME to $$END_TIME"

# Update config with time range
sed -i "s/start_time: .*/start_time: \"$$START_TIME\"/" /opt/redshift-test-drive/config/extract.yaml
sed -i "s/end_time: .*/end_time: \"$$END_TIME\"/" /opt/redshift-test-drive/config/extract.yaml

# Run extraction
python3 extract.py -c /opt/redshift-test-drive/config/extract.yaml
EOF

# Replay workload script
cat > /opt/redshift-test-drive/replay-workload.sh << 'EOF'
#!/bin/bash
cd /opt/redshift-test-drive/repo/core
source venv/bin/activate 2>/dev/null || {
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
}

TARGET=$${1:-sales}
CONFIG_FILE="/opt/redshift-test-drive/config/replay-$${TARGET}.yaml"

if [ ! -f "$$CONFIG_FILE" ]; then
  echo "Error: Configuration file $$CONFIG_FILE not found"
  echo "Usage: $$0 [sales|ops]"
  exit 1
fi

echo "Replaying workload to $$TARGET consumer"
python3 replay.py -c "$$CONFIG_FILE"
EOF

# Make scripts executable
chmod +x /opt/redshift-test-drive/extract-workload.sh
chmod +x /opt/redshift-test-drive/replay-workload.sh

# Set permissions
chown -R testdrive:testdrive /opt/redshift-test-drive
chmod -R 755 /opt/redshift-test-drive

# Create systemd service for monitoring (optional)
cat > /etc/systemd/system/test-drive-monitor.service << EOF
[Unit]
Description=Redshift Test Drive Monitor
After=network.target

[Service]
Type=simple
User=testdrive
WorkingDirectory=/opt/redshift-test-drive
ExecStart=/usr/bin/python3 /opt/redshift-test-drive/monitor.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Configure AWS credentials (will use instance profile)
echo "Configuring AWS..."
aws configure set region ${aws_region}

# Test connectivity to Redshift clusters
echo "Testing Redshift connectivity..."
export PGPASSWORD="${redshift_password}"

# Test producer
psql -h $(echo ${producer_endpoint} | cut -d: -f1) \
     -p 5439 \
     -U ${redshift_user} \
     -d ${redshift_database} \
     -c "SELECT 1" || echo "Warning: Could not connect to producer"

# Test sales consumer
psql -h $(echo ${consumer_sales_endpoint} | cut -d: -f1) \
     -p 5439 \
     -U ${redshift_user} \
     -d ${redshift_database} \
     -c "SELECT 1" || echo "Warning: Could not connect to sales consumer"

# Test ops consumer
psql -h $(echo ${consumer_ops_endpoint} | cut -d: -f1) \
     -p 5439 \
     -U ${redshift_user} \
     -d ${redshift_database} \
     -c "SELECT 1" || echo "Warning: Could not connect to ops consumer"

# Create README for users
cat > /opt/redshift-test-drive/README.md << 'EOF'
# Redshift Test Drive Setup

This instance is configured for Redshift Test Drive operations.

## Quick Start

1. Switch to test drive user:
   ```
   sudo su - testdrive
   ```

2. Extract workload from audit logs:
   ```
   /opt/redshift-test-drive/extract-workload.sh
   ```
   Or specify time range:
   ```
   /opt/redshift-test-drive/extract-workload.sh "2024-01-01 00:00:00" "2024-01-02 00:00:00"
   ```

3. Replay workload to consumer:
   ```
   # For sales consumer
   /opt/redshift-test-drive/replay-workload.sh sales
   
   # For operations consumer
   /opt/redshift-test-drive/replay-workload.sh ops
   ```

## Configuration Files

- Extract: `/opt/redshift-test-drive/config/extract.yaml`
- Replay Sales: `/opt/redshift-test-drive/config/replay-sales.yaml`
- Replay Ops: `/opt/redshift-test-drive/config/replay-ops.yaml`

## Logs

- User data log: `/var/log/user-data.log`
- Test Drive logs: `/opt/redshift-test-drive/logs/`

## S3 Buckets

- Audit logs: `${audit_logs_bucket}`
- Workload storage: `${workload_bucket}`
EOF

echo "======================================"
echo "Redshift Test Drive setup complete at $(date)!"
echo "Instance is ready for use. SSH in and switch to 'testdrive' user to begin."
echo "======================================"

# Create a completion marker file
touch /var/log/user-data-complete
echo "Setup completed at $(date)" > /var/log/user-data-complete