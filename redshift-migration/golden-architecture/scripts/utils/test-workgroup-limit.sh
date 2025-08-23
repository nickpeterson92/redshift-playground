#!/bin/bash

# Test the actual workgroup limit by checking existing resources

echo "=== Testing Workgroup Limits ==="
echo ""

# Count existing workgroups
TOTAL_WG=$(aws redshift-serverless list-workgroups --query 'length(workgroups)' --output text)
echo "Current workgroups: $TOTAL_WG"

# List all workgroups with their creation order
echo ""
echo "Existing workgroups:"
aws redshift-serverless list-workgroups \
    --query 'workgroups[*].[workgroupName,status,createdAt]' \
    --output table

# Check if there's a pattern in what's working
echo ""
echo "Workgroup creation pattern:"
for i in {1..10}; do
    WG_NAME="airline-consumer-wg-$i"
    STATUS=$(aws redshift-serverless get-workgroup \
        --workgroup-name "$WG_NAME" \
        --query 'workgroup.status' \
        --output text 2>/dev/null || echo "NOT_EXISTS")
    
    if [ "$STATUS" != "NOT_EXISTS" ]; then
        echo "  Consumer $i: $STATUS"
    else
        echo "  Consumer $i: Not created"
    fi
done

echo ""
echo "=== Hypothesis ==="
echo ""
echo "Based on the pattern:"
echo "- You have $TOTAL_WG total workgroups"
echo "- Consumer 6 is stuck in MODIFYING"
echo "- Consumers 4 and 5 were likely never created"
echo ""
echo "Possible causes:"
echo "1. Hard limit of 5-6 workgroups per account in your organization"
echo "2. The 6th workgroup hit the limit and got stuck"
echo "3. Sequential locking prevented 4 and 5 from being created"
echo ""
echo "Recommendations:"
echo "1. Try to delete consumer 6 and see if it frees up the slot:"
echo "   terraform destroy -target='module.consumers[5]'"
echo ""
echo "2. Check with your AWS admin about workgroup limits"
echo ""
echo "3. Consider using fewer, larger workgroups instead of many small ones"
echo "   (e.g., 3 workgroups with 64 RPU instead of 6 with 32 RPU)"