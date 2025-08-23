#!/bin/bash
# Simple visual demonstration of NLB architecture

REGION="${1:-us-west-2}"

echo "
╔════════════════════════════════════════════════════════════════╗
║           NLB → REDSHIFT SERVERLESS ARCHITECTURE               ║
╚════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────┐
│                     Network Load Balancer                    │
│                    (airline-redshift-nlb)                    │
│                         Port: 5439                           │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼ Distributes traffic to 9 IPs
┌─────────────────────────────────────────────────────────────┐
│                      Target Group                            │
│                   (airline-consumers)                        │
│                    Type: IP targets                          │
└─────────────────────────────────────────────────────────────┘
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  Consumer 1   │    │  Consumer 2   │    │  Consumer 3   │
│   Workgroup   │    │   Workgroup   │    │   Workgroup   │
├───────────────┤    ├───────────────┤    ├───────────────┤
│ VPC Endpoint  │    │ VPC Endpoint  │    │ VPC Endpoint  │
├───────────────┤    ├───────────────┤    ├───────────────┤
│ ENI (AZ-a) IP │    │ ENI (AZ-a) IP │    │ ENI (AZ-a) IP │
│ ENI (AZ-b) IP │    │ ENI (AZ-b) IP │    │ ENI (AZ-b) IP │
│ ENI (AZ-c) IP │    │ ENI (AZ-c) IP │    │ ENI (AZ-c) IP │
└───────────────┘    └───────────────┘    └───────────────┘
      3 IPs               3 IPs               3 IPs
                    Total: 9 IP targets
"

echo "Fetching actual data..."
echo "────────────────────────────────────────────────────────"

# Get actual NLB DNS
NLB_DNS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query 'LoadBalancers[?contains(LoadBalancerName, `redshift-nlb`)].DNSName' \
  --output text | head -n1)

echo "🔗 NLB Endpoint: ${NLB_DNS:-Not found}"

# Count workgroups
NUM_WORKGROUPS=$(aws redshift-serverless list-workgroups \
  --region "$REGION" \
  --query 'length(workgroups[?contains(workgroupName, `consumer`)])' \
  --output text)

echo "📦 Consumer Workgroups: ${NUM_WORKGROUPS:-0}"

# Count targets
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --region "$REGION" \
  --query 'TargetGroups[?contains(TargetGroupName, `consumers`)].TargetGroupArn' \
  --output text | head -n1)

if [ -n "$TARGET_GROUP_ARN" ]; then
  NUM_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --region "$REGION" \
    --query 'length(TargetHealthDescriptions)' \
    --output text)
  
  HEALTHY=$(aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --region "$REGION" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
    --output text)
  
  echo "🎯 Target IPs: $NUM_TARGETS (Healthy: $HEALTHY)"
  echo "✅ Formula: $NUM_WORKGROUPS workgroups × 3 AZs = $NUM_TARGETS IPs"
fi

echo "
💡 Why 9 IPs?
   Each Redshift Serverless workgroup needs high availability,
   so it creates network interfaces in multiple AZs. The NLB
   must target these individual IPs, not the DNS names.
"