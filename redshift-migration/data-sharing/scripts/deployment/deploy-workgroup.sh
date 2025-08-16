#!/bin/bash

# Unified deployment script for Redshift Serverless workgroups
# Handles both sequential locking and waiting for availability
# Can be used for both producer and consumer workgroups

set -e

# Parameters
NAMESPACE_NAME="${1:?Error: Namespace name required}"
WORKGROUP_NAME="${2:?Error: Workgroup name required}"
WORKGROUP_TYPE="${3:-consumer}"  # producer or consumer
CONSUMER_INDEX="${4:-1}"

# Configuration
LOCK_DIR="/tmp/redshift-consumer-lock.d"
LOCK_FILE="$LOCK_DIR/lock"
MAX_WAIT=600  # 10 minutes max wait
LOCK_TIMEOUT=600  # Lock expires after 10 minutes

echo "[${NAMESPACE_NAME}] Starting deployment for ${WORKGROUP_TYPE} workgroup: ${WORKGROUP_NAME}"

# Create lock directory if it doesn't exist
mkdir -p "$LOCK_DIR"

# Function to acquire lock atomically
acquire_lock() {
    local my_id="$$-${NAMESPACE_NAME}"
    local attempt=0
    local wait_time=0
    
    while [ $wait_time -lt $MAX_WAIT ]; do
        # Try to create lock atomically using mkdir (which is atomic)
        if mkdir "$LOCK_FILE" 2>/dev/null; then
            # We got the lock, write our details
            echo "$my_id" > "$LOCK_FILE/owner"
            echo "$WORKGROUP_NAME" > "$LOCK_FILE/workgroup"
            echo "$(date +%s)" > "$LOCK_FILE/timestamp"
            echo "$WORKGROUP_TYPE" > "$LOCK_FILE/type"
            echo "[${NAMESPACE_NAME}] Lock acquired successfully"
            return 0
        fi
        
        # Lock exists, check if it's stale
        if [ -f "$LOCK_FILE/timestamp" ]; then
            local lock_time=$(cat "$LOCK_FILE/timestamp" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local lock_age=$((current_time - lock_time))
            
            if [ $lock_age -gt $LOCK_TIMEOUT ]; then
                echo "[${NAMESPACE_NAME}] Found stale lock (${lock_age}s old), removing..."
                rm -rf "$LOCK_FILE"
                continue
            fi
        fi
        
        # Lock is held by someone else
        local owner=$(cat "$LOCK_FILE/owner" 2>/dev/null || echo "unknown")
        local lock_workgroup=$(cat "$LOCK_FILE/workgroup" 2>/dev/null || echo "unknown")
        
        if [ $((attempt % 10)) -eq 0 ]; then
            echo "[${NAMESPACE_NAME}] Waiting for lock... Currently held by: $owner (creating $lock_workgroup)"
        fi
        
        sleep 2
        wait_time=$((wait_time + 2))
        attempt=$((attempt + 1))
    done
    
    echo "[${NAMESPACE_NAME}] ERROR: Failed to acquire lock after ${MAX_WAIT} seconds"
    return 1
}

# Function to release lock
release_lock() {
    if [ -f "$LOCK_FILE/workgroup" ]; then
        local lock_workgroup=$(cat "$LOCK_FILE/workgroup" 2>/dev/null || echo "")
        if [ "$lock_workgroup" == "$WORKGROUP_NAME" ]; then
            echo "[${NAMESPACE_NAME}] Releasing lock..."
            rm -rf "$LOCK_FILE"
        fi
    fi
}

# Function to wait for workgroup to become available
wait_for_workgroup() {
    echo "[${NAMESPACE_NAME}] Waiting for workgroup ${WORKGROUP_NAME} to become available..."
    
    local start_time=$(date +%s)
    local attempt=0
    
    while true; do
        # Check workgroup status
        local status=$(aws redshift-serverless get-workgroup \
            --workgroup-name "${WORKGROUP_NAME}" \
            --query 'workgroup.status' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        echo "[${NAMESPACE_NAME}] Workgroup status: $status (attempt $attempt, elapsed: ${elapsed}s)"
        
        if [ "$status" == "AVAILABLE" ]; then
            echo "[${NAMESPACE_NAME}] ✅ Workgroup is now available!"
            
            # Get endpoint details for confirmation
            local endpoint=$(aws redshift-serverless get-workgroup \
                --workgroup-name "${WORKGROUP_NAME}" \
                --query 'workgroup.endpoint.address' \
                --output text 2>/dev/null || echo "N/A")
            echo "[${NAMESPACE_NAME}] Endpoint: $endpoint"
            
            # Get VPC endpoint if it exists
            if [ "$WORKGROUP_TYPE" == "consumer" ]; then
                local vpc_endpoint=$(aws redshift-serverless list-endpoint-access \
                    --query "endpoints[?workgroupName=='${WORKGROUP_NAME}'].address | [0]" \
                    --output text 2>/dev/null || echo "N/A")
                if [ "$vpc_endpoint" != "N/A" ] && [ "$vpc_endpoint" != "None" ]; then
                    echo "[${NAMESPACE_NAME}] VPC Endpoint: $vpc_endpoint"
                fi
            fi
            
            return 0
        elif [ "$status" == "CREATING" ] || [ "$status" == "MODIFYING" ]; then
            # Still in progress, keep waiting
            if [ $((attempt % 5)) -eq 0 ]; then
                echo "[${NAMESPACE_NAME}] Still ${status}, waiting..."
            fi
        elif [ "$status" == "NOT_FOUND" ]; then
            # Check if namespace exists
            local ns_status=$(aws redshift-serverless get-namespace \
                --namespace-name "${NAMESPACE_NAME}" \
                --query 'namespace.status' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$ns_status" == "NOT_FOUND" ]; then
                echo "[${NAMESPACE_NAME}] ERROR: Namespace does not exist!"
                return 1
            else
                echo "[${NAMESPACE_NAME}] Namespace exists ($ns_status), workgroup pending creation..."
            fi
        else
            echo "[${NAMESPACE_NAME}] WARNING: Unexpected status: $status"
        fi
        
        # Check timeout
        if [ $elapsed -gt $MAX_WAIT ]; then
            echo "[${NAMESPACE_NAME}] ERROR: Timeout after ${MAX_WAIT} seconds"
            return 1
        fi
        
        sleep 3
        attempt=$((attempt + 1))
    done
}

# Main execution
main() {
    echo "[${NAMESPACE_NAME}] ========================================="
    echo "[${NAMESPACE_NAME}] Deployment Configuration:"
    echo "[${NAMESPACE_NAME}]   Type: ${WORKGROUP_TYPE}"
    echo "[${NAMESPACE_NAME}]   Namespace: ${NAMESPACE_NAME}"
    echo "[${NAMESPACE_NAME}]   Workgroup: ${WORKGROUP_NAME}"
    if [ "$WORKGROUP_TYPE" == "consumer" ]; then
        echo "[${NAMESPACE_NAME}]   Consumer Index: ${CONSUMER_INDEX}"
    fi
    echo "[${NAMESPACE_NAME}] ========================================="
    
    # For consumer workgroups, acquire lock first
    if [ "$WORKGROUP_TYPE" == "consumer" ]; then
        echo "[${NAMESPACE_NAME}] Acquiring deployment lock..."
        if ! acquire_lock; then
            echo "[${NAMESPACE_NAME}] Failed to acquire lock, exiting"
            exit 1
        fi
    else
        echo "[${NAMESPACE_NAME}] Producer workgroup - no lock required"
    fi
    
    # Set up trap to release lock on exit
    trap release_lock EXIT
    
    # Now the workgroup can be created by Terraform
    echo "[${NAMESPACE_NAME}] Lock acquired. Terraform can now create the workgroup."
    echo "[${NAMESPACE_NAME}] Waiting for Terraform to create workgroup..."
    
    # Brief pause to let Terraform start
    sleep 5
    
    # Wait for workgroup to become available
    if wait_for_workgroup; then
        echo "[${NAMESPACE_NAME}] ✅ Deployment complete!"
        
        # Brief stabilization period
        echo "[${NAMESPACE_NAME}] Allowing 5 seconds for stabilization..."
        sleep 5
        
        # Release lock for next consumer
        if [ "$WORKGROUP_TYPE" == "consumer" ]; then
            release_lock
            echo "[${NAMESPACE_NAME}] Lock released for next consumer"
        fi
        
        echo "[${NAMESPACE_NAME}] ========================================="
        echo "[${NAMESPACE_NAME}] SUCCESS: ${WORKGROUP_NAME} is ready!"
        echo "[${NAMESPACE_NAME}] ========================================="
        exit 0
    else
        echo "[${NAMESPACE_NAME}] ❌ Deployment failed!"
        exit 1
    fi
}

# Run main function
main