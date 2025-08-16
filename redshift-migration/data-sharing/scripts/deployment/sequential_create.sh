#!/bin/bash

# Sequential creation script with atomic lock operations
# This script ensures only one consumer is created at a time

set -e

NAMESPACE_NAME="$1"
WORKGROUP_NAME="$2"
CONSUMER_INDEX="$3"
LOCK_DIR="/tmp/redshift-consumer-lock.d"
LOCK_FILE="$LOCK_DIR/lock"
MAX_WAIT=600  # 10 minutes max wait

echo "[${NAMESPACE_NAME}] Starting sequential creation process..."

# Create lock directory if it doesn't exist
mkdir -p "$LOCK_DIR"

# Function to acquire lock atomically
acquire_lock() {
    local my_id="$$-${NAMESPACE_NAME}"
    local attempt=0
    
    while true; do
        # Try to create lock atomically using mkdir (which is atomic)
        if mkdir "$LOCK_FILE" 2>/dev/null; then
            # We got the lock, write our ID
            echo "$my_id" > "$LOCK_FILE/owner"
            echo "$WORKGROUP_NAME" > "$LOCK_FILE/workgroup"
            echo "$(date +%s)" > "$LOCK_FILE/timestamp"
            echo "[${NAMESPACE_NAME}] Lock acquired successfully"
            return 0
        fi
        
        # Lock exists, check if it's stale
        if [ -f "$LOCK_FILE/timestamp" ]; then
            local lock_time=$(cat "$LOCK_FILE/timestamp" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local lock_age=$((current_time - lock_time))
            
            if [ $lock_age -gt 600 ]; then
                echo "[${NAMESPACE_NAME}] Found stale lock (${lock_age}s old), removing..."
                rm -rf "$LOCK_FILE"
                continue
            fi
        fi
        
        # Lock is held by someone else
        local owner=$(cat "$LOCK_FILE/owner" 2>/dev/null || echo "unknown")
        local workgroup=$(cat "$LOCK_FILE/workgroup" 2>/dev/null || echo "unknown")
        echo "[${NAMESPACE_NAME}] Waiting for lock held by $owner (workgroup: $workgroup)..."
        
        # Check the status of the workgroup holding the lock
        if [ "$workgroup" != "unknown" ]; then
            local status=$(aws redshift-serverless get-workgroup --workgroup-name "$workgroup" --query 'workgroup.status' --output text 2>/dev/null || echo "NOT_FOUND")
            echo "[${NAMESPACE_NAME}]   Status of $workgroup: $status"
            
            # If the workgroup is available or not found, the lock might be stale
            if [ "$status" == "AVAILABLE" ] || [ "$status" == "NOT_FOUND" ]; then
                echo "[${NAMESPACE_NAME}]   Workgroup $workgroup is $status, lock might be stale"
                # Wait a bit more to be sure
                sleep 30
                # Re-check status
                status=$(aws redshift-serverless get-workgroup --workgroup-name "$workgroup" --query 'workgroup.status' --output text 2>/dev/null || echo "NOT_FOUND")
                if [ "$status" == "AVAILABLE" ] || [ "$status" == "NOT_FOUND" ]; then
                    echo "[${NAMESPACE_NAME}]   Removing apparently stale lock"
                    rm -rf "$LOCK_FILE"
                    continue
                fi
            fi
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -gt 60 ]; then  # 60 * 10s = 600s = 10 minutes
            echo "[${NAMESPACE_NAME}] ERROR: Timeout waiting for lock"
            exit 1
        fi
        
        sleep 10
    done
}

# Function to release lock
release_lock() {
    if [ -d "$LOCK_FILE" ]; then
        local owner=$(cat "$LOCK_FILE/owner" 2>/dev/null || echo "unknown")
        local my_id="$$-${NAMESPACE_NAME}"
        
        if [ "$owner" == "$my_id" ]; then
            echo "[${NAMESPACE_NAME}] Releasing lock..."
            rm -rf "$LOCK_FILE"
        else
            echo "[${NAMESPACE_NAME}] WARNING: Lock owned by $owner, not releasing"
        fi
    fi
}

# Ensure lock is released on exit
trap release_lock EXIT

# Small random wait to reduce initial contention (0-3 seconds)
initial_wait=$((RANDOM % 4))
if [ $initial_wait -gt 0 ]; then
    echo "[${NAMESPACE_NAME}] Brief wait (${initial_wait}s) to reduce contention..."
    sleep $initial_wait
fi

# Acquire the lock
acquire_lock

# Now we have exclusive access, check current state
echo "[${NAMESPACE_NAME}] Checking current workgroup states..."
aws redshift-serverless list-workgroups --query 'workgroups[*].[workgroupName,status]' --output table || true

# Check if any workgroup is currently creating/modifying
creating_count=$(aws redshift-serverless list-workgroups --query 'length(workgroups[?status==`CREATING`])' --output text 2>/dev/null || echo "0")
modifying_count=$(aws redshift-serverless list-workgroups --query 'length(workgroups[?status==`MODIFYING`])' --output text 2>/dev/null || echo "0")

if [ "$creating_count" -gt 0 ] || [ "$modifying_count" -gt 0 ]; then
    echo "[${NAMESPACE_NAME}] Found $creating_count creating and $modifying_count modifying workgroups"
    echo "[${NAMESPACE_NAME}] Waiting for them to complete..."
    
    # Wait for all workgroups to be available
    wait_count=0
    while true; do
        creating_count=$(aws redshift-serverless list-workgroups --query 'length(workgroups[?status==`CREATING`])' --output text 2>/dev/null || echo "0")
        modifying_count=$(aws redshift-serverless list-workgroups --query 'length(workgroups[?status==`MODIFYING`])' --output text 2>/dev/null || echo "0")
        
        if [ "$creating_count" -eq 0 ] && [ "$modifying_count" -eq 0 ]; then
            echo "[${NAMESPACE_NAME}] All workgroups are stable, proceeding..."
            break
        fi
        
        wait_count=$((wait_count + 1))
        if [ $wait_count -gt 60 ]; then  # 10 minutes
            echo "[${NAMESPACE_NAME}] WARNING: Timeout waiting for workgroups to stabilize"
            break
        fi
        
        echo "[${NAMESPACE_NAME}]   Still waiting: $creating_count creating, $modifying_count modifying..."
        sleep 10
    done
fi

# Now we can proceed with creation
echo "[${NAMESPACE_NAME}] Lock acquired, ready for workgroup creation"
echo "[${NAMESPACE_NAME}] Lock will be released after ensuring no conflicts"

# Brief hold to ensure AWS API registers our intent
# This is much shorter than before - just enough to avoid API race conditions
sleep 5

echo "[${NAMESPACE_NAME}] Sequential creation controller complete"
# Lock released via trap - next consumer can now acquire it