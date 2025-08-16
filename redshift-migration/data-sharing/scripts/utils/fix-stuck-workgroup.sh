#!/bin/bash

# Fix stuck workgroups in MODIFYING state

WORKGROUP="${1:-airline-consumer-wg-6}"

echo "Checking workgroup: $WORKGROUP"

# Get current status
STATUS=$(aws redshift-serverless get-workgroup \
    --workgroup-name "$WORKGROUP" \
    --query 'workgroup.status' \
    --output text 2>/dev/null)

echo "Current status: $STATUS"

if [ "$STATUS" = "MODIFYING" ]; then
    echo "Workgroup is stuck in MODIFYING state"
    
    # Option 1: Try to update a config parameter to trigger state change
    echo "Attempting to trigger state change by updating config..."
    aws redshift-serverless update-workgroup \
        --workgroup-name "$WORKGROUP" \
        --config-parameters parameterKey=max_query_execution_time,parameterValue=3601 \
        2>/dev/null || echo "Update failed (expected if still modifying)"
    
    sleep 5
    
    # Check status again
    NEW_STATUS=$(aws redshift-serverless get-workgroup \
        --workgroup-name "$WORKGROUP" \
        --query 'workgroup.status' \
        --output text 2>/dev/null)
    
    echo "New status: $NEW_STATUS"
    
    if [ "$NEW_STATUS" = "MODIFYING" ]; then
        echo ""
        echo "Workgroup still stuck. Options:"
        echo "1. Wait longer (sometimes takes 10-15 minutes)"
        echo "2. Delete and recreate the workgroup:"
        echo "   terraform destroy -target=module.consumers[5]"
        echo "   terraform apply -target=module.consumers[5]"
        echo "3. Check AWS Support/Service Health Dashboard for issues"
        
        # Check how long it's been modifying
        echo ""
        echo "Checking CloudTrail for when modification started..."
        aws cloudtrail lookup-events \
            --lookup-attributes AttributeKey=ResourceName,AttributeValue="$WORKGROUP" \
            --max-items 5 \
            --query 'Events[*].[EventTime,EventName]' \
            --output table 2>/dev/null || echo "Unable to check CloudTrail"
    fi
elif [ "$STATUS" = "AVAILABLE" ]; then
    echo "✓ Workgroup is available"
else
    echo "Workgroup status: $STATUS"
fi

# Clear any stale locks
LOCK_FILE="/tmp/redshift-consumer-lock.d/lock"
if [ -d "$LOCK_FILE" ]; then
    echo ""
    echo "Clearing stale lock..."
    rm -rf "$LOCK_FILE"
    echo "Lock cleared"
fi