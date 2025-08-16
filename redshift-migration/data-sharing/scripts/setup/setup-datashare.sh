#!/bin/bash

# Data Sharing Setup Script
# =========================
# This script automates data sharing setup for Redshift Serverless
# It only configures data sharing for newly deployed consumers

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a consumer already has data sharing configured
check_consumer_configured() {
    local consumer_namespace_id=$1
    local producer_endpoint=$2
    local database=$3
    local username=$4
    local password=$5
    
    # Query to check if airline_shared database exists
    local check_query="SELECT COUNT(*) FROM svv_redshift_databases WHERE database_name = 'airline_shared';"
    
    # Execute query and capture result
    local result=$(PGPASSWORD="$password" psql \
        -h "$producer_endpoint" \
        -p 5439 \
        -U "$username" \
        -d "$database" \
        -t \
        -c "$check_query" 2>/dev/null || echo "0")
    
    # Return 0 if configured (database exists), 1 if not
    if [[ "$result" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to setup data sharing on producer
setup_producer_datashare() {
    local producer_endpoint=$1
    local database=$2
    local username=$3
    local password=$
    local consumer_namespace_ids=$5
    
    log_info "Setting up data sharing on producer..."
    
    # Create datashare if not exists
    local setup_query=$(cat <<EOF
-- Check if datashare exists
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM svv_datashares WHERE share_name = 'airline_share'
    ) THEN
        EXECUTE 'CREATE DATASHARE airline_share SET PUBLICACCESSIBLE TRUE';
    END IF;
END \$\$;

-- Add schema if not already added
ALTER DATASHARE airline_share ADD SCHEMA airline_dw;

-- Add all tables in schema
ALTER DATASHARE airline_share ADD ALL TABLES IN SCHEMA airline_dw;
EOF
)
    
    # Execute setup query
    PGPASSWORD="$password" psql \
        -h "$producer_endpoint" \
        -p 5439 \
        -U "$username" \
        -d "$database" \
        -c "$setup_query"
    
    # Grant access to consumer namespaces
    IFS=',' read -ra NAMESPACE_IDS <<< "$consumer_namespace_ids"
    for namespace_id in "${NAMESPACE_IDS[@]}"; do
        namespace_id=$(echo "$namespace_id" | tr -d ' ')
        
        log_info "Granting access to consumer namespace: $namespace_id"
        
        grant_query="GRANT USAGE ON DATASHARE airline_share TO NAMESPACE '$namespace_id';"
        
        PGPASSWORD="$password" psql \
            -h "$producer_endpoint" \
            -p 5439 \
            -U "$username" \
            -d "$database" \
            -c "$grant_query"
    done
    
    log_info "Producer datashare setup complete"
}

# Function to setup data sharing on consumer
setup_consumer_datashare() {
    local consumer_endpoint=$1
    local consumer_namespace_id=$2
    local producer_namespace_id=$3
    local database=$4
    local username=$5
    local password=$6
    
    log_info "Setting up data sharing on consumer: $consumer_endpoint"
    
    # Create database from datashare
    local setup_query=$(cat <<EOF
-- Create database from producer's datashare
CREATE DATABASE IF NOT EXISTS airline_shared 
FROM DATASHARE airline_share 
OF NAMESPACE '$producer_namespace_id';

-- Verify access
SELECT COUNT(*) as table_count
FROM svv_all_tables
WHERE database_name = 'airline_shared';
EOF
)
    
    # Execute setup query
    PGPASSWORD="$password" psql \
        -h "$consumer_endpoint" \
        -p 5439 \
        -U "$username" \
        -d "$database" \
        -c "$setup_query"
    
    log_info "Consumer datashare setup complete for: $consumer_endpoint"
}

# Main function
main() {
    # Check for required arguments
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 <terraform_output_json> [--new-consumers-only]"
        exit 1
    fi
    
    local terraform_output=$1
    local new_consumers_only=false
    
    if [[ "$2" == "--new-consumers-only" ]]; then
        new_consumers_only=true
    fi
    
    # Parse Terraform output
    if [[ ! -f "$terraform_output" ]]; then
        # If not a file, assume it's JSON string
        echo "$terraform_output" > /tmp/terraform_output.json
        terraform_output="/tmp/terraform_output.json"
    fi
    
    # Extract values from Terraform output
    local producer_endpoint=$(jq -r '.producer_endpoint.value[0].address' "$terraform_output")
    local producer_namespace_id=$(jq -r '.producer_namespace_id.value' "$terraform_output")
    local master_username=$(jq -r '.master_username.value' "$terraform_output")
    local master_password=$(jq -r '.master_password.value' "$terraform_output")
    local database_name=$(jq -r '.database_name.value' "$terraform_output")
    
    # Get consumer information
    local consumer_count=$(jq -r '.consumer_endpoints.value | length' "$terraform_output")
    local consumer_namespace_ids=$(jq -r '.consumer_namespace_ids.value | join(",")' "$terraform_output")
    
    log_info "Found $consumer_count consumers to process"
    
    # Setup producer datashare
    setup_producer_datashare \
        "$producer_endpoint" \
        "$database_name" \
        "$master_username" \
        "$master_password" \
        "$consumer_namespace_ids"
    
    # Setup consumers
    for ((i=0; i<$consumer_count; i++)); do
        local consumer_endpoint=$(jq -r ".consumer_endpoints.value[$i][0].address" "$terraform_output")
        local consumer_namespace_id=$(jq -r ".consumer_namespace_ids.value[$i]" "$terraform_output")
        
        if [[ "$new_consumers_only" == true ]]; then
            # Check if consumer already has data sharing configured
            if check_consumer_configured "$consumer_namespace_id" "$consumer_endpoint" "$database_name" "$master_username" "$master_password"; then
                log_info "Consumer $consumer_endpoint already configured, skipping..."
                continue
            fi
        fi
        
        setup_consumer_datashare \
            "$consumer_endpoint" \
            "$consumer_namespace_id" \
            "$producer_namespace_id" \
            "$database_name" \
            "$master_username" \
            "$master_password"
    done
    
    log_info "Data sharing setup complete!"
}

# Run main function
main "$@"