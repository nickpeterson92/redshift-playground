#!/bin/bash

# Check CloudTrail and CloudWatch events for workgroup issues

WORKGROUP="${1:-airline-consumer-wg-6}"
echo "=== Checking events for $WORKGROUP ==="
echo ""

# Check CloudTrail for creation/modification events
echo "1. CloudTrail Events for $WORKGROUP:"
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue="$WORKGROUP" \
    --max-items 10 \
    --query 'Events[*].[EventTime,EventName,ErrorCode,ErrorMessage]' \
    --output table

echo ""
echo "2. Recent Redshift Serverless API Errors:"
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=CreateWorkgroup \
    --max-items 5 \
    --query 'Events[?ErrorCode!=null].[EventTime,ResourceName,ErrorCode,ErrorMessage]' \
    --output table

echo ""
echo "3. Checking for Namespace Issues:"
# The namespace must exist before workgroup
NAMESPACE="airline-consumer-6"
aws redshift-serverless get-namespace \
    --namespace-name "$NAMESPACE" \
    --query 'namespace.{Name:namespaceName,Status:status}' \
    --output json 2>/dev/null || echo "Namespace not found"

echo ""
echo "4. VPC Endpoint Status:"
# Check if VPC endpoint creation failed
aws ec2 describe-vpc-endpoints \
    --filters "Name=tag:Name,Values=*consumer*6*" \
    --query 'VpcEndpoints[*].[VpcEndpointId,State,StateMessage]' \
    --output table 2>/dev/null || echo "No VPC endpoint found"

echo ""
echo "5. Common Stuck State Causes:"
echo "   • VPC endpoint creation failed (network resource limits)"
echo "   • Namespace not ready when workgroup tried to create"
echo "   • IAM role propagation delay"
echo "   • AWS backend issue (rare but happens)"
echo "   • Concurrent modification attempt (our locking should prevent this)"

echo ""
echo "6. Checking System Events:"
# Check AWS Health Dashboard events
aws health describe-events \
    --filter services=REDSHIFT \
    --query 'events[*].[eventTypeCode,statusCode,startTime]' \
    --output table 2>/dev/null || echo "Unable to check AWS Health (need health:DescribeEvents permission)"

echo ""
echo "=== Analysis ==="
if [ "$(aws redshift-serverless get-workgroup --workgroup-name $WORKGROUP --query 'workgroup.status' --output text 2>/dev/null)" == "DELETING" ]; then
    echo "• Workgroup is DELETING - it never became AVAILABLE"
    echo "• This typically means resource allocation failed"
    echo "• NOT a quota error (would fail immediately with clear error)"
    echo "• Likely a resource constraint or AWS internal issue"
fi