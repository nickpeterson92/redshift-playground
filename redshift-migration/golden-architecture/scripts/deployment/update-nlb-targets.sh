#!/bin/bash

# Script to dynamically update NLB target group with consumer endpoints
# This runs after consumers are created to avoid Terraform lifecycle issues

set -e

PROJECT_NAME="${1:-airline}"
REGION="${2:-us-west-2}"

echo "Updating NLB target group for project: $PROJECT_NAME"

# Get target group ARN
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --names "${PROJECT_NAME}-consumers" \
  --region "$REGION" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null || echo "")

if [ -z "$TARGET_GROUP_ARN" ]; then
  echo "Target group not found: ${PROJECT_NAME}-consumers"
  exit 1
fi

echo "Target group ARN: $TARGET_GROUP_ARN"

# Get current registered targets
echo "Getting current targets..."
CURRENT_TARGETS=$(aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'TargetHealthDescriptions[*].Target.Id' \
  --output text 2>/dev/null || echo "")

# Get consumer workgroups
echo "Finding consumer workgroups..."
WORKGROUPS=$(aws redshift-serverless list-workgroups \
  --region "$REGION" \
  --query "workgroups[?contains(workgroupName, '${PROJECT_NAME}-consumer')].workgroupName" \
  --output text)

if [ -z "$WORKGROUPS" ]; then
  echo "No consumer workgroups found"
  exit 0
fi

# Process each workgroup
for WORKGROUP in $WORKGROUPS; do
  echo "Processing workgroup: $WORKGROUP"
  
  # Get the endpoint name for this workgroup
  ENDPOINT_NAME="${WORKGROUP}-endpoint"
  
  # Get the managed VPC endpoint IPs directly from Redshift Serverless
  IPS=$(aws redshift-serverless get-endpoint-access \
    --endpoint-name "$ENDPOINT_NAME" \
    --region "$REGION" \
    --query 'endpoint.vpcEndpoint.networkInterfaces[*].privateIpAddress' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$IPS" ]; then
    echo "  No IPs found for endpoint: $ENDPOINT_NAME"
  else
    echo "  Found IPs for $ENDPOINT_NAME: $IPS"
    
    # Register each IP as a target
    for IP in $IPS; do
      if [ -n "$IP" ]; then
        if echo "$CURRENT_TARGETS" | grep -q "$IP"; then
          echo "  Target already registered: $IP"
        else
          echo "  Registering target: $IP:5439"
          aws elbv2 register-targets \
            --target-group-arn "$TARGET_GROUP_ARN" \
            --targets Id="$IP",Port=5439 \
            --region "$REGION" || true
        fi
      fi
    done
  fi
done

# Clean up any targets that no longer exist
echo "Cleaning up stale targets..."
if [ -n "$CURRENT_TARGETS" ]; then
  for TARGET in $CURRENT_TARGETS; do
    # Check if this target still corresponds to an active workgroup
    FOUND=false
    for WORKGROUP in $WORKGROUPS; do
      ENDPOINT_NAME="${WORKGROUP}-endpoint"
      
      # Get the managed VPC endpoint IPs directly from Redshift Serverless
      IPS=$(aws redshift-serverless get-endpoint-access \
        --endpoint-name "$ENDPOINT_NAME" \
        --region "$REGION" \
        --query 'endpoint.vpcEndpoint.networkInterfaces[*].privateIpAddress' \
        --output text 2>/dev/null || echo "")
        
      if echo "$IPS" | grep -q "$TARGET"; then
        FOUND=true
        break
      fi
    done
    
    if [ "$FOUND" = false ]; then
      echo "  Deregistering stale target: $TARGET"
      aws elbv2 deregister-targets \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --targets Id="$TARGET",Port=5439 \
        --region "$REGION" || true
    fi
  done
fi

echo "NLB target group update complete"

# Show final target health
echo "Final target health:"
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State]' \
  --output table