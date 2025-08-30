#!/bin/bash
# Test script to verify NLB target counting

PROJECT_NAME="airline"
REGION="us-west-2"

echo "Testing NLB target configuration..."
echo "=================================="

# Get target group ARN
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --names "${PROJECT_NAME}-consumers" \
  --region "$REGION" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null)

if [ -z "$TARGET_GROUP_ARN" ]; then
  echo "Target group not found: ${PROJECT_NAME}-consumers"
  exit 1
fi

echo "Target group: ${PROJECT_NAME}-consumers"
echo ""

# Get target health
echo "Current target health:"
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# Count targets by state
HEALTHY=$(aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
  --output text)

TOTAL=$(aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'TargetHealthDescriptions | length(@)' \
  --output text)

# Count consumer workgroups
CONSUMER_COUNT=$(aws redshift-serverless list-workgroups \
  --region "$REGION" \
  --query "workgroups[?contains(workgroupName, '${PROJECT_NAME}-consumer')] | length(@)" \
  --output text)

echo ""
echo "Summary:"
echo "--------"
echo "Consumer workgroups: $CONSUMER_COUNT"
echo "Expected targets: $CONSUMER_COUNT (1 managed VPC endpoint per consumer)"
echo "Total targets registered: $TOTAL"
echo "Healthy targets: $HEALTHY"

if [ "$HEALTHY" -eq "$CONSUMER_COUNT" ]; then
  echo ""
  echo "✅ Target configuration is correct: $HEALTHY/$CONSUMER_COUNT healthy"
else
  echo ""
  echo "⚠️  Target health check in progress: $HEALTHY/$CONSUMER_COUNT healthy"
fi