#!/bin/bash

# Centralized deployment logging utility
# Logs to both local file and optionally to CloudWatch

set -e

# Configuration
LOG_DIR="/tmp/redshift-deployment-logs"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
CLOUDWATCH_GROUP="/aws/redshift/deployment"
CLOUDWATCH_STREAM="deployment-$(date +%Y%m%d)"
ENABLE_CLOUDWATCH="${ENABLE_CLOUDWATCH:-false}"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log messages
log_message() {
    local level="$1"
    local component="$2"
    local message="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Format: [TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
    local log_entry="[$timestamp] [$level] [$component] $message"
    
    # Write to local file
    echo "$log_entry" >> "$LOG_FILE"
    
    # Also echo to console
    echo "$log_entry"
    
    # Send to CloudWatch if enabled
    if [ "$ENABLE_CLOUDWATCH" = "true" ]; then
        send_to_cloudwatch "$timestamp" "$level" "$component" "$message"
    fi
}

# Function to send logs to CloudWatch
send_to_cloudwatch() {
    local timestamp="$1"
    local level="$2"
    local component="$3"
    local message="$4"
    
    # Create log group if it doesn't exist
    aws logs create-log-group --log-group-name "$CLOUDWATCH_GROUP" 2>/dev/null || true
    
    # Create log stream if it doesn't exist
    aws logs create-log-stream \
        --log-group-name "$CLOUDWATCH_GROUP" \
        --log-stream-name "$CLOUDWATCH_STREAM" 2>/dev/null || true
    
    # Put log event
    aws logs put-log-events \
        --log-group-name "$CLOUDWATCH_GROUP" \
        --log-stream-name "$CLOUDWATCH_STREAM" \
        --log-events timestamp=$(date +%s000),message="[$level] [$component] $message" 2>/dev/null || true
}

# Function to log workgroup status
log_workgroup_status() {
    local workgroup_name="$1"
    local namespace_name="$2"
    
    # Get detailed workgroup status
    local status_json=$(aws redshift-serverless get-workgroup \
        --workgroup-name "$workgroup_name" 2>/dev/null || echo "{}")
    
    if [ "$status_json" != "{}" ]; then
        local status=$(echo "$status_json" | jq -r '.workgroup.status')
        local base_capacity=$(echo "$status_json" | jq -r '.workgroup.baseCapacity')
        local max_capacity=$(echo "$status_json" | jq -r '.workgroup.maxCapacity')
        
        log_message "INFO" "$workgroup_name" "Status: $status, BaseCapacity: $base_capacity, MaxCapacity: $max_capacity"
        
        # If modifying, try to get more details
        if [ "$status" = "MODIFYING" ]; then
            log_message "WARN" "$workgroup_name" "Workgroup is in MODIFYING state - checking for issues"
            
            # Check recent events
            local events=$(aws redshift-serverless list-snapshots \
                --namespace-name "$namespace_name" \
                --max-items 5 2>/dev/null || echo "[]")
            
            if [ "$events" != "[]" ]; then
                log_message "INFO" "$workgroup_name" "Recent snapshots: $events"
            fi
        fi
    else
        log_message "ERROR" "$workgroup_name" "Failed to get workgroup status"
    fi
}

# Function to log namespace status
log_namespace_status() {
    local namespace_name="$1"
    
    local status_json=$(aws redshift-serverless get-namespace \
        --namespace-name "$namespace_name" 2>/dev/null || echo "{}")
    
    if [ "$status_json" != "{}" ]; then
        local status=$(echo "$status_json" | jq -r '.namespace.status')
        local iam_roles=$(echo "$status_json" | jq -r '.namespace.iamRoles[]' 2>/dev/null | tr '\n' ',')
        
        log_message "INFO" "$namespace_name" "Namespace Status: $status, IAM Roles: ${iam_roles:-none}"
    else
        log_message "ERROR" "$namespace_name" "Failed to get namespace status"
    fi
}

# Function to check for lock conflicts
check_lock_status() {
    local lock_file="/tmp/redshift-consumer-lock.d/lock"
    
    if [ -d "$lock_file" ]; then
        local owner=$(cat "$lock_file/owner" 2>/dev/null || echo "unknown")
        local workgroup=$(cat "$lock_file/workgroup" 2>/dev/null || echo "unknown")
        local timestamp=$(cat "$lock_file/timestamp" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local lock_age=$((current_time - timestamp))
        
        log_message "INFO" "LOCK" "Lock held by: $owner for workgroup: $workgroup (age: ${lock_age}s)"
        
        # Check if lock is stale
        if [ $lock_age -gt 600 ]; then
            log_message "WARN" "LOCK" "Lock appears stale (>10 minutes old)"
        fi
    else
        log_message "INFO" "LOCK" "No active lock found"
    fi
}

# Function to tail and monitor log
monitor_log() {
    echo "Monitoring deployment log: $LOG_FILE"
    echo "Press Ctrl+C to stop monitoring"
    echo "----------------------------------------"
    tail -f "$LOG_FILE"
}

# Main execution based on arguments
case "${1:-log}" in
    "log")
        # Log a message
        level="${2:-INFO}"
        component="${3:-GENERAL}"
        message="${4:-No message provided}"
        log_message "$level" "$component" "$message"
        ;;
    
    "workgroup")
        # Log workgroup status
        workgroup_name="$2"
        namespace_name="$3"
        log_workgroup_status "$workgroup_name" "$namespace_name"
        ;;
    
    "namespace")
        # Log namespace status
        namespace_name="$2"
        log_namespace_status "$namespace_name"
        ;;
    
    "lock")
        # Check lock status
        check_lock_status
        ;;
    
    "monitor")
        # Monitor the log file
        monitor_log
        ;;
    
    "summary")
        # Show deployment summary
        echo "=== Deployment Log Summary ==="
        echo "Log file: $LOG_FILE"
        echo ""
        echo "Error count: $(grep -c '\[ERROR\]' "$LOG_FILE" 2>/dev/null || echo 0)"
        echo "Warning count: $(grep -c '\[WARN\]' "$LOG_FILE" 2>/dev/null || echo 0)"
        echo ""
        echo "Recent errors:"
        grep '\[ERROR\]' "$LOG_FILE" 2>/dev/null | tail -5 || echo "No errors found"
        echo ""
        echo "Recent warnings:"
        grep '\[WARN\]' "$LOG_FILE" 2>/dev/null | tail -5 || echo "No warnings found"
        ;;
    
    *)
        echo "Usage: $0 {log|workgroup|namespace|lock|monitor|summary} [args...]"
        echo ""
        echo "Commands:"
        echo "  log [level] [component] [message]  - Log a message"
        echo "  workgroup [name] [namespace]        - Log workgroup status"
        echo "  namespace [name]                    - Log namespace status"
        echo "  lock                                - Check lock status"
        echo "  monitor                             - Tail the log file"
        echo "  summary                             - Show log summary"
        echo ""
        echo "Environment variables:"
        echo "  ENABLE_CLOUDWATCH=true             - Enable CloudWatch logging"
        exit 1
        ;;
esac