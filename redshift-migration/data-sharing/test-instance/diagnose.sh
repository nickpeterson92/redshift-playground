#!/bin/bash

# Diagnostic script to troubleshoot NLB connectivity

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get instance IP
INSTANCE_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")

if [ -z "$INSTANCE_IP" ]; then
    echo -e "${RED}❌ Could not get instance IP${NC}"
    exit 1
fi

echo -e "${GREEN}🔍 Running connectivity diagnostics${NC}"
echo -e "${YELLOW}EC2 Instance: $INSTANCE_IP${NC}"
echo "========================================="

# Test 1: Basic SSH connectivity
echo -e "\n${YELLOW}1. Testing SSH connectivity...${NC}"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i test-instance.pem ec2-user@$INSTANCE_IP \
    "echo '✅ SSH connection successful'" || echo "❌ SSH failed"

# Test 2: Check if psql is installed
echo -e "\n${YELLOW}2. Checking psql installation...${NC}"
ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
    "which psql && psql --version || echo '❌ psql not found'"

# Test 3: DNS resolution of NLB
echo -e "\n${YELLOW}3. Testing NLB DNS resolution...${NC}"
NLB_ENDPOINT="airline-redshift-nlb-7a0ce4765dc4ed98.elb.us-west-2.amazonaws.com"
ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
    "nslookup $NLB_ENDPOINT || dig $NLB_ENDPOINT +short || echo '❌ DNS resolution failed'"

# Test 4: Network connectivity to NLB
echo -e "\n${YELLOW}4. Testing network connectivity to NLB (port 5439)...${NC}"
ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
    "timeout 5 nc -zv $NLB_ENDPOINT 5439 2>&1 || echo '❌ Cannot reach NLB on port 5439'"

# Test 5: Check NLB target health from AWS CLI
echo -e "\n${YELLOW}5. Checking NLB target health...${NC}"
aws elbv2 describe-target-health \
    --target-group-arn $(aws elbv2 describe-target-groups --names "airline-consumers" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null) \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
    --output table 2>/dev/null || echo "❌ Could not check target health"

# Test 6: Check security groups
echo -e "\n${YELLOW}6. Checking security group rules...${NC}"
ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
    "curl -s http://169.254.169.254/latest/meta-data/security-groups || echo '❌ Cannot get security groups'"

# Test 7: Try telnet to NLB
echo -e "\n${YELLOW}7. Testing telnet to NLB...${NC}"
ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
    "timeout 5 bash -c 'exec 3<>/dev/tcp/$NLB_ENDPOINT/5439 && echo ✅ Port 5439 is open || echo ❌ Port 5439 is closed' 2>&1"

# Test 8: Check if test scripts exist
echo -e "\n${YELLOW}8. Checking test scripts...${NC}"
ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE_IP \
    "ls -la ~/redshift-tests/ 2>/dev/null || echo '❌ Test scripts directory not found'"

echo -e "\n${GREEN}Diagnostics complete!${NC}"
echo "========================================="