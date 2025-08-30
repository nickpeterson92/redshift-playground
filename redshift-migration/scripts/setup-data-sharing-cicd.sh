#!/bin/bash
# Data Sharing Setup Script for CI/CD Pipeline
# This script runs on Harness delegate to configure data sharing between clusters

set -e

# Configuration from environment variables (set in Harness pipeline)
PRODUCER_HOST="${PRODUCER_HOST}"
CONSUMER1_HOST="${CONSUMER1_HOST}"
CONSUMER2_HOST="${CONSUMER2_HOST}"
CONSUMER3_HOST="${CONSUMER3_HOST}"
DB_USER="${DB_USER:-awsuser}"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${DB_NAME:-dev}"

# Consumer namespace IDs (from Terraform outputs)
CONSUMER1_NS="${CONSUMER1_NAMESPACE}"
CONSUMER2_NS="${CONSUMER2_NAMESPACE}"
CONSUMER3_NS="${CONSUMER3_NAMESPACE}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Data Sharing Setup for Redshift Clusters ===${NC}"

# Function to run SQL on a specific cluster
run_sql() {
    local host=$1
    local sql=$2
    local description=$3
    
    echo -e "${YELLOW}Running on ${host}: ${description}${NC}"
    PGPASSWORD="${DB_PASSWORD}" psql -h "${host}" -U "${DB_USER}" -d "${DB_NAME}" -p 5439 -c "${sql}"
}

# Step 1: Get Producer Namespace
echo -e "${GREEN}Step 1: Getting producer namespace...${NC}"
PRODUCER_NS=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${PRODUCER_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p 5439 -t -c "SELECT current_namespace;" | tr -d ' ')
echo "Producer namespace: ${PRODUCER_NS}"

# Step 2: Create datashares on producer
echo -e "${GREEN}Step 2: Creating datashares on producer...${NC}"

# Create airline core share
run_sql "${PRODUCER_HOST}" \
    "CREATE DATASHARE IF NOT EXISTS airline_core_share SET PUBLICACCESSIBLE TRUE;" \
    "Creating airline_core_share"

run_sql "${PRODUCER_HOST}" \
    "ALTER DATASHARE airline_core_share ADD SCHEMA shared_airline;" \
    "Adding shared_airline schema"

run_sql "${PRODUCER_HOST}" \
    "ALTER DATASHARE airline_core_share ADD ALL TABLES IN SCHEMA shared_airline;" \
    "Adding all tables from shared_airline"

# Create sales domain share
run_sql "${PRODUCER_HOST}" \
    "CREATE DATASHARE IF NOT EXISTS sales_data_share SET PUBLICACCESSIBLE TRUE;" \
    "Creating sales_data_share"

run_sql "${PRODUCER_HOST}" \
    "ALTER DATASHARE sales_data_share ADD SCHEMA sales_domain;" \
    "Adding sales_domain schema"

run_sql "${PRODUCER_HOST}" \
    "ALTER DATASHARE sales_data_share ADD ALL TABLES IN SCHEMA sales_domain;" \
    "Adding all tables from sales_domain"

# Create operations domain share
run_sql "${PRODUCER_HOST}" \
    "CREATE DATASHARE IF NOT EXISTS operations_data_share SET PUBLICACCESSIBLE TRUE;" \
    "Creating operations_data_share"

run_sql "${PRODUCER_HOST}" \
    "ALTER DATASHARE operations_data_share ADD SCHEMA operations_domain;" \
    "Adding operations_domain schema"

run_sql "${PRODUCER_HOST}" \
    "ALTER DATASHARE operations_data_share ADD ALL TABLES IN SCHEMA operations_domain;" \
    "Adding all tables from operations_domain"

# Step 3: Grant access to consumer namespaces
echo -e "${GREEN}Step 3: Granting access to consumer namespaces...${NC}"

for share in airline_core_share sales_data_share operations_data_share; do
    for ns in "${CONSUMER1_NS}" "${CONSUMER2_NS}" "${CONSUMER3_NS}"; do
        run_sql "${PRODUCER_HOST}" \
            "GRANT USAGE ON DATASHARE ${share} TO NAMESPACE '${ns}';" \
            "Granting ${share} to namespace ${ns}"
    done
done

# Step 4: Create databases from shares on each consumer
echo -e "${GREEN}Step 4: Creating databases from shares on consumers...${NC}"

# Consumer 1
run_sql "${CONSUMER1_HOST}" \
    "CREATE DATABASE IF NOT EXISTS airline_shared FROM DATASHARE airline_core_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating airline_shared database on Consumer 1"

run_sql "${CONSUMER1_HOST}" \
    "CREATE DATABASE IF NOT EXISTS sales_analytics FROM DATASHARE sales_data_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating sales_analytics database on Consumer 1"

run_sql "${CONSUMER1_HOST}" \
    "CREATE DATABASE IF NOT EXISTS operations_analytics FROM DATASHARE operations_data_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating operations_analytics database on Consumer 1"

# Consumer 2
run_sql "${CONSUMER2_HOST}" \
    "CREATE DATABASE IF NOT EXISTS airline_shared FROM DATASHARE airline_core_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating airline_shared database on Consumer 2"

run_sql "${CONSUMER2_HOST}" \
    "CREATE DATABASE IF NOT EXISTS sales_analytics FROM DATASHARE sales_data_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating sales_analytics database on Consumer 2"

run_sql "${CONSUMER2_HOST}" \
    "CREATE DATABASE IF NOT EXISTS operations_analytics FROM DATASHARE operations_data_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating operations_analytics database on Consumer 2"

# Consumer 3
run_sql "${CONSUMER3_HOST}" \
    "CREATE DATABASE IF NOT EXISTS airline_shared FROM DATASHARE airline_core_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating airline_shared database on Consumer 3"

run_sql "${CONSUMER3_HOST}" \
    "CREATE DATABASE IF NOT EXISTS sales_analytics FROM DATASHARE sales_data_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating sales_analytics database on Consumer 3"

run_sql "${CONSUMER3_HOST}" \
    "CREATE DATABASE IF NOT EXISTS operations_analytics FROM DATASHARE operations_data_share OF NAMESPACE '${PRODUCER_NS}';" \
    "Creating operations_analytics database on Consumer 3"

# Step 5: Verify data sharing
echo -e "${GREEN}Step 5: Verifying data sharing...${NC}"

for consumer_host in "${CONSUMER1_HOST}" "${CONSUMER2_HOST}" "${CONSUMER3_HOST}"; do
    echo -e "${YELLOW}Verifying on ${consumer_host}${NC}"
    
    # Check shared airline data
    count=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${consumer_host}" -U "${DB_USER}" -d "${DB_NAME}" -p 5439 -t -c \
        "SELECT COUNT(*) FROM airline_shared.shared_airline.airports;" | tr -d ' ')
    echo "  - Airports count: ${count}"
    
    # Check sales data
    count=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${consumer_host}" -U "${DB_USER}" -d "${DB_NAME}" -p 5439 -t -c \
        "SELECT COUNT(*) FROM sales_analytics.sales_domain.customers;" | tr -d ' ')
    echo "  - Customers count: ${count}"
    
    # Check operations data
    count=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${consumer_host}" -U "${DB_USER}" -d "${DB_NAME}" -p 5439 -t -c \
        "SELECT COUNT(*) FROM operations_analytics.operations_domain.maintenance_logs;" | tr -d ' ')
    echo "  - Maintenance logs count: ${count}"
done

echo -e "${GREEN}=== Data Sharing Setup Complete ===${NC}"