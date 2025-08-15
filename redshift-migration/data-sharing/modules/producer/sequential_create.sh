#!/bin/bash

# Sequential creation script for producer
# Uses same atomic lock as consumers to prevent conflicts

set -e

NAMESPACE_NAME="$1"
WORKGROUP_NAME="$2"
LOCK_DIR="/tmp/redshift-consumer-lock.d"
LOCK_FILE="$LOCK_DIR/lock"
MAX_WAIT=600  # 10 minutes max wait

echo "[${NAMESPACE_NAME}] Starting producer creation process..."

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

# Acquire the lock
acquire_lock

# Now we have exclusive access
echo "[${NAMESPACE_NAME}] Lock acquired, ready for producer workgroup creation"

# Brief hold to ensure AWS API registers our intent
sleep 5

echo "[${NAMESPACE_NAME}] Producer creation controller complete"
# Lock released via trap