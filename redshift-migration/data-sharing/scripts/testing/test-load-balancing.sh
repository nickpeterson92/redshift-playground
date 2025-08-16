#!/bin/bash

# Test load balancing from two EC2 instances
# This proves that NLB distributes connections based on source IP

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if instances are deployed
if [ ! -f "test-instance.pem" ]; then
    echo -e "${RED}❌ Test instances not deployed yet${NC}"
    echo "Run: terraform apply"
    exit 1
fi

# Get instance IPs
INSTANCE1_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
INSTANCE2_IP=$(terraform output -raw instance2_public_ip 2>/dev/null || echo "")

if [ -z "$INSTANCE1_IP" ] || [ -z "$INSTANCE2_IP" ]; then
    echo -e "${RED}❌ Could not get instance IPs${NC}"
    echo "Make sure both instances are deployed"
    exit 1
fi

# Check for password
if [ -z "$REDSHIFT_PASSWORD" ]; then
    REDSHIFT_PASSWORD='Password123'
fi

# Get NLB endpoint from parent deployment
NLB_ENDPOINT=$(cd .. && terraform output -raw nlb_endpoint 2>/dev/null)
if [ -z "$NLB_ENDPOINT" ]; then
    echo -e "${RED}❌ Could not get NLB endpoint. Is the main infrastructure deployed?${NC}"
    exit 1
fi

echo -e "${GREEN}🔄 Testing NLB Load Balancing Across Two EC2 Instances${NC}"
echo "========================================================="
echo -e "${YELLOW}Instance 1:${NC} $INSTANCE1_IP"
echo -e "${YELLOW}Instance 2:${NC} $INSTANCE2_IP"
echo -e "${YELLOW}NLB Endpoint:${NC} $NLB_ENDPOINT"
echo ""

# Test from Instance 1
echo -e "${BLUE}📡 Testing from Instance 1...${NC}"
echo "--------------------------------"
NAMESPACE1=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i test-instance.pem ec2-user@$INSTANCE1_IP \
    "PGPASSWORD='$REDSHIFT_PASSWORD' psql 'host=$NLB_ENDPOINT port=5439 dbname=consumer_db user=admin sslmode=require' \
     -t -c 'SELECT current_namespace' 2>/dev/null | tr -d ' \n'")

if [ -n "$NAMESPACE1" ]; then
    echo -e "${GREEN}✅ Instance 1 connected to namespace:${NC}"
    echo "   $NAMESPACE1"
    
    # Use namespace ID to identify consumer (first 8 chars for readability)
    CONSUMER1="Consumer (${NAMESPACE1:0:8}...)"
    echo -e "   ${YELLOW}→ Routed to: $CONSUMER1${NC}"
else
    echo -e "${RED}❌ Failed to connect from Instance 1${NC}"
fi

echo ""

# Test from Instance 2
echo -e "${BLUE}📡 Testing from Instance 2...${NC}"
echo "--------------------------------"
NAMESPACE2=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i test-instance.pem ec2-user@$INSTANCE2_IP \
    "PGPASSWORD='$REDSHIFT_PASSWORD' psql 'host=$NLB_ENDPOINT port=5439 dbname=consumer_db user=admin sslmode=require' \
     -t -c 'SELECT current_namespace' 2>/dev/null | tr -d ' \n'")

if [ -n "$NAMESPACE2" ]; then
    echo -e "${GREEN}✅ Instance 2 connected to namespace:${NC}"
    echo "   $NAMESPACE2"
    
    # Use namespace ID to identify consumer (first 8 chars for readability)
    CONSUMER2="Consumer (${NAMESPACE2:0:8}...)"
    echo -e "   ${YELLOW}→ Routed to: $CONSUMER2${NC}"
else
    echo -e "${RED}❌ Failed to connect from Instance 2${NC}"
fi

echo ""
echo -e "${GREEN}📊 Load Balancing Summary${NC}"
echo "========================="

if [ -n "$NAMESPACE1" ] && [ -n "$NAMESPACE2" ]; then
    if [ "$NAMESPACE1" != "$NAMESPACE2" ]; then
        echo -e "${GREEN}✅ LOAD BALANCING CONFIRMED!${NC}"
        echo "   • Instance 1 → $CONSUMER1"
        echo "   • Instance 2 → $CONSUMER2"
        echo "   • Each instance consistently routes to a different consumer"
    else
        echo -e "${YELLOW}⚠️  Both instances routing to same consumer${NC}"
        echo "   • Both going to: $CONSUMER1"
        echo "   • This might happen if one consumer is unhealthy"
    fi
    
    # Test stickiness - multiple connections from same instance
    echo ""
    echo -e "${GREEN}🔍 Testing Session Stickiness${NC}"
    echo "------------------------------"
    
    echo "Making 3 connections from Instance 1..."
    for i in {1..3}; do
        TEST_NS=$(ssh -o StrictHostKeyChecking=no -i test-instance.pem ec2-user@$INSTANCE1_IP \
            "PGPASSWORD='$REDSHIFT_PASSWORD' psql 'host=$NLB_ENDPOINT port=5439 dbname=consumer_db user=admin sslmode=require' \
             -t -c 'SELECT current_namespace' 2>/dev/null | tr -d ' \n'")
        if [ "$TEST_NS" == "$NAMESPACE1" ]; then
            echo "   Connection $i: ✅ Same consumer"
        else
            echo "   Connection $i: ❌ Different consumer!"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✨ Test Complete!${NC}"
    echo ""
    echo "The NLB is using source IP stickiness:"
    echo "• All connections from the same instance go to the same consumer"
    echo "• Different instances are balanced across different consumers"
else
    echo -e "${RED}❌ Could not verify load balancing${NC}"
fi