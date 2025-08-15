#!/bin/bash

# Post-creation script that waits for producer workgroup to be available
# This runs AFTER Terraform creates the workgroup resource
# It ensures the workgroup is fully ready before releasing the lock

set -e

WORKGROUP_NAME="$1"
NAMESPACE_NAME="$2"
MAX_WAIT=600  # 10 minutes
LOCK_DIR="/tmp/redshift-consumer-lock.d"
LOCK_FILE="$LOCK_DIR/lock"

echo "[${NAMESPACE_NAME}] Waiting for producer workgroup ${WORKGROUP_NAME} to become available..."

start_time=$(date +%s)
attempt=0

while true; do
    # Check workgroup status
    status=$(aws redshift-serverless get-workgroup --workgroup-name "${WORKGROUP_NAME}" --query 'workgroup.status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    echo "[${NAMESPACE_NAME}] Producer workgroup status: $status (attempt $attempt)"
    
    if [ "$status" == "AVAILABLE" ]; then
        echo "[${NAMESPACE_NAME}] ✅ Producer workgroup is now available!"
        
        # Get endpoint details for confirmation
        endpoint=$(aws redshift-serverless get-workgroup --workgroup-name "${WORKGROUP_NAME}" --query 'workgroup.endpoint.address' --output text 2>/dev/null || echo "N/A")
        echo "[${NAMESPACE_NAME}] Producer endpoint: $endpoint"
        
        # Clean up our lock if we still hold it
        if [ -f "$LOCK_FILE/workgroup" ]; then
            lock_workgroup=$(cat "$LOCK_FILE/workgroup" 2>/dev/null || echo "")
            if [ "$lock_workgroup" == "$WORKGROUP_NAME" ]; then
                echo "[${NAMESPACE_NAME}] Releasing producer lock..."
                rm -rf "$LOCK_FILE"
            fi
        fi
        
        # Very brief stabilization
        sleep 5
        
        break
    elif [ "$status" == "CREATING" ] || [ "$status" == "MODIFYING" ]; then
        # Still in progress, keep waiting
        echo "[${NAMESPACE_NAME}] Producer still ${status}, waiting..."
    elif [ "$status" == "NOT_FOUND" ]; then
        # Check if Terraform is still creating it by looking at the namespace
        namespace_exists=$(aws redshift-serverless get-namespace --namespace-name "${NAMESPACE_NAME}" --query 'namespace.namespaceName' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$namespace_exists" != "NOT_FOUND" ]; then
            # Namespace exists but workgroup not yet - Terraform is likely still submitting the request
            if [ $attempt -lt 6 ]; then
                echo "[${NAMESPACE_NAME}] Producer workgroup not visible yet (namespace exists), AWS API propagating..."
            else
                echo "[${NAMESPACE_NAME}] Producer workgroup still not visible after ${attempt} attempts, waiting..."
            fi
        else
            echo "[${NAMESPACE_NAME}] Neither namespace nor workgroup found, waiting for Terraform..."
        fi
    else
        echo "[${NAMESPACE_NAME}] ⚠️ Unexpected producer status: $status"
    fi
    
    # Check timeout
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [ $elapsed -gt $MAX_WAIT ]; then
        echo "[${NAMESPACE_NAME}] ❌ Timeout waiting for producer workgroup to become available"
        exit 1
    fi
    
    attempt=$((attempt + 1))
    sleep 10
done

echo "[${NAMESPACE_NAME}] Producer workgroup ready, consumers can now proceed"