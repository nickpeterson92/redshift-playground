#!/bin/bash

# Run Load Test Script for Redshift Consumer Clusters
# This script runs an intensive load test to generate audit logs

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=================================${NC}"
echo -e "${GREEN}Redshift Consumer Load Test${NC}"
echo -e "${GREEN}=================================${NC}"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}Error: terraform.tfvars not found!${NC}"
    echo "Please create terraform.tfvars with your Redshift credentials"
    exit 1
fi

# Extract password from terraform.tfvars
MASTER_PASSWORD=$(grep master_password terraform.tfvars | cut -d'"' -f2)
if [ -z "$MASTER_PASSWORD" ]; then
    echo -e "${RED}Error: Could not extract master_password from terraform.tfvars${NC}"
    exit 1
fi

# Get cluster endpoints using Terraform output
echo -e "${YELLOW}Getting cluster endpoints...${NC}"
SALES_ENDPOINT=$(terraform output -raw consumer_sales_cluster_endpoint 2>/dev/null | cut -d: -f1)
OPS_ENDPOINT=$(terraform output -raw consumer_operations_cluster_endpoint 2>/dev/null | cut -d: -f1)

if [ -z "$SALES_ENDPOINT" ] || [ -z "$OPS_ENDPOINT" ]; then
    echo -e "${RED}Error: Could not get cluster endpoints. Make sure Terraform has been applied.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Sales Consumer: $SALES_ENDPOINT${NC}"
echo -e "${GREEN}✓ Ops Consumer: $OPS_ENDPOINT${NC}"

# Default parameters
DATABASE="mydb"
USERNAME="admin"
PORT=5439
DURATION=2.0  # hours
THREADS=20

# Allow overriding duration and threads
if [ ! -z "$1" ]; then
    DURATION=$1
fi
if [ ! -z "$2" ]; then
    THREADS=$2
fi

echo ""
echo -e "${YELLOW}Test Configuration:${NC}"
echo "  Duration: $DURATION hours"
echo "  Threads: $THREADS concurrent connections"
echo "  Database: $DATABASE"
echo "  Username: $USERNAME"
echo ""

# Check if Python dependencies are installed
echo -e "${YELLOW}Checking Python dependencies...${NC}"
python3 -c "import psycopg2" 2>/dev/null || {
    echo -e "${RED}psycopg2 not installed. Installing...${NC}"
    pip3 install psycopg2-binary
}

# Confirm before starting
echo -e "${YELLOW}This will generate intense load on both consumer clusters for $DURATION hours.${NC}"
read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Load test cancelled."
    exit 0
fi

# Run the load test
echo ""
echo -e "${GREEN}Starting load test...${NC}"
echo "Press Ctrl+C to stop early"
echo ""

python3 load-test-consumers.py \
    --sales-host "$SALES_ENDPOINT" \
    --sales-database "$DATABASE" \
    --sales-user "$USERNAME" \
    --sales-password "$MASTER_PASSWORD" \
    --sales-port $PORT \
    --ops-host "$OPS_ENDPOINT" \
    --ops-database "$DATABASE" \
    --ops-user "$USERNAME" \
    --ops-password "$MASTER_PASSWORD" \
    --ops-port $PORT \
    --duration $DURATION \
    --threads $THREADS

echo ""
echo -e "${GREEN}Load test complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Wait 2-3 hours for audit logs to appear in S3"
echo "2. Check S3 bucket for logs:"
terraform output -raw redshift_logs_s3_bucket 2>/dev/null && echo ""
echo "3. Use AWS CLI to list logs:"
echo "   aws s3 ls s3://\$(terraform output -raw redshift_logs_s3_bucket)/"
echo ""
echo "4. Download logs for analysis:"
echo "   aws s3 sync s3://\$(terraform output -raw redshift_logs_s3_bucket)/ ./audit-logs/"