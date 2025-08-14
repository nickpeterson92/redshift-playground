#!/bin/bash

# Seamless remote test execution script
# This runs the test scripts on the EC2 instance but displays output locally

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if instance is deployed
if [ ! -f "test-instance.pem" ]; then
    echo -e "${RED}❌ Test instance not deployed yet${NC}"
    echo "Run: terraform apply"
    exit 1
fi

# Get instance IP from Terraform
INSTANCE_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")

if [ -z "$INSTANCE_IP" ]; then
    echo -e "${RED}❌ Could not get instance IP${NC}"
    exit 1
fi

# Check for password
if [ -z "$REDSHIFT_PASSWORD" ]; then
    echo -e "${YELLOW}No REDSHIFT_PASSWORD environment variable found${NC}"
    echo -n "Enter Redshift password: "
    read -s REDSHIFT_PASSWORD
    echo
else
    echo -e "${GREEN}✓ Using REDSHIFT_PASSWORD from environment${NC}"
fi

# Test type selection
if [ "$1" == "python" ]; then
    echo -e "${GREEN}🐍 Running Python test on EC2 instance...${NC}"
    ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
        "cd redshift-tests && REDSHIFT_PASSWORD='$REDSHIFT_PASSWORD' python3 test-nlb-connection.py"
elif [ "$1" == "bash" ]; then
    echo -e "${GREEN}🔧 Running Bash test on EC2 instance...${NC}"
    ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
        "cd redshift-tests && REDSHIFT_PASSWORD='$REDSHIFT_PASSWORD' ./test-nlb.sh"
else
    # Default to quick connectivity test
    echo -e "${GREEN}⚡ Running quick connectivity test on EC2 instance...${NC}"
    echo -e "${YELLOW}Connecting to EC2: $INSTANCE_IP${NC}"
    # Get NLB endpoint from parent deployment
    NLB_ENDPOINT=$(cd .. && terraform output -raw nlb_endpoint 2>/dev/null)
    if [ -z "$NLB_ENDPOINT" ]; then
        echo -e "${RED}❌ Could not get NLB endpoint. Is the main infrastructure deployed?${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Target NLB: $NLB_ENDPOINT${NC}"
    
    # Run the psql command with explicit error handling
    # Note: We connect to consumer_db first, then query the shared database
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i test-instance.pem ec2-user@$INSTANCE_IP \
        "export PGPASSWORD='$REDSHIFT_PASSWORD' && \
         echo 'Testing NLB connection from within VPC...' && \
         echo 'Connecting to consumer database to query shared data...' && \
         psql 'host=$NLB_ENDPOINT port=5439 dbname=consumer_db user=admin sslmode=require' \
              -c 'SELECT current_database(), current_namespace;' \
              -c 'SELECT * FROM airline_shared.airline_dw.dim_aircraft LIMIT 10;' \
              -c 'SELECT * FROM airline_shared.airline_dw.dim_airport LIMIT 10;' \
              -c 'SELECT * FROM airline_shared.airline_dw.dim_customer LIMIT 10;' \
         2>&1 || echo 'Connection failed. Check if datashare is configured on consumers.'"
fi