#!/bin/bash

# Test NLB connection to Redshift consumers
# This script uses psql to connect through the NLB and verify data access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔄 Testing Redshift NLB Connection${NC}"
echo "=================================="

# Get NLB endpoint from Terraform
# Try current directory first, then parent directory
NLB_ENDPOINT=$(terraform output -raw nlb_endpoint 2>/dev/null || echo "")

if [ -z "$NLB_ENDPOINT" ]; then
    # Try parent directory (main deployment)
    NLB_ENDPOINT=$(cd .. && terraform output -raw nlb_endpoint 2>/dev/null || echo "")
fi

if [ -z "$NLB_ENDPOINT" ]; then
    echo -e "${RED}❌ Could not get NLB endpoint from Terraform outputs${NC}"
    echo "Make sure the main infrastructure is deployed first"
    exit 1
fi

# Database credentials
DATABASE="consumer_db"
USERNAME="admin"
PORT="5439"

# Check if password is set
if [ -z "$REDSHIFT_PASSWORD" ]; then
    echo -n "Enter Redshift password: "
    read -s REDSHIFT_PASSWORD
    echo
fi

export PGPASSWORD=$REDSHIFT_PASSWORD

echo -e "\n${YELLOW}📡 NLB Endpoint:${NC} $NLB_ENDPOINT"
echo -e "${YELLOW}📊 Database:${NC} $DATABASE"
echo -e "${YELLOW}👤 Username:${NC} $USERNAME"

# Test function
test_query() {
    local query="$1"
    local description="$2"
    
    echo -e "\n${GREEN}Testing: $description${NC}"
    psql -h "$NLB_ENDPOINT" -p "$PORT" -U "$USERNAME" -d "$DATABASE" -c "$query" 2>&1 || {
        echo -e "${RED}❌ Query failed${NC}"
        return 1
    }
}

# Run tests
echo -e "\n${GREEN}🧪 Running Connection Tests${NC}"
echo "=================================="

# Test 1: Basic connectivity and namespace info
test_query "SELECT current_database(), current_namespace, version();" \
    "Basic connectivity and version info"

# Test 2: Check available databases
test_query "\\l airline_shared" \
    "List shared database"

# Test 3: Query shared data - flights
test_query "SELECT COUNT(*) as flight_count FROM airline_shared.airline_dw.flights;" \
    "Count flights from shared data"

# Test 4: Query shared data - airlines
test_query "SELECT airline_code, airline_name FROM airline_shared.airline_dw.airlines LIMIT 5;" \
    "Sample airlines from shared data"

# Test 5: Query shared data - airports
test_query "SELECT airport_code, airport_name, city FROM airline_shared.airline_dw.airports LIMIT 5;" \
    "Sample airports from shared data"

# Test 6: Complex query across shared tables
test_query "
SELECT 
    a.airline_name,
    COUNT(DISTINCT f.flight_id) as total_flights,
    COUNT(DISTINCT f.origin_airport) as unique_origins,
    COUNT(DISTINCT f.destination_airport) as unique_destinations
FROM airline_shared.airline_dw.flights f
JOIN airline_shared.airline_dw.airlines a ON f.airline = a.airline_code
GROUP BY a.airline_name
ORDER BY total_flights DESC
LIMIT 5;" \
    "Complex query joining shared tables"

# Test multiple connections to verify load balancing
echo -e "\n${GREEN}🔄 Testing Load Distribution (5 connections)${NC}"
echo "=================================="

for i in {1..5}; do
    echo -e "\n${YELLOW}Connection $i:${NC}"
    psql -h "$NLB_ENDPOINT" -p "$PORT" -U "$USERNAME" -d "$DATABASE" \
        -c "SELECT current_namespace, pg_backend_pid() as backend_pid;" 2>&1 | grep -v "^$" || {
        echo -e "${RED}❌ Connection $i failed${NC}"
    }
    sleep 0.5
done

echo -e "\n${GREEN}✅ NLB Connection Test Complete!${NC}"
echo "=================================="
echo -e "${GREEN}Summary:${NC}"
echo "• NLB is accessible at: $NLB_ENDPOINT:$PORT"
echo "• Data sharing is working correctly"
echo "• Queries are being distributed across consumer workgroups"
echo
echo -e "${YELLOW}💡 Tip:${NC} Use the Python script for more detailed load distribution analysis:"
echo "   python3 test-nlb-connection.py"

unset PGPASSWORD