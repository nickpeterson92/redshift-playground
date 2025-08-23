#!/bin/bash
# Demonstrate NLB → Redshift Serverless architecture with clear evidence

PROJECT_NAME="${1:-airline}"
REGION="${2:-us-west-2}"

echo "========================================================================="
echo "   NLB → REDSHIFT SERVERLESS ARCHITECTURE DEMONSTRATION"
echo "========================================================================="

# 1. Show NLB Configuration
echo -e "\n📍 STEP 1: NETWORK LOAD BALANCER"
echo "-----------------------------------------"
NLB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${PROJECT_NAME}-redshift-nlb" \
  --region "$REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>/dev/null || echo "")

if [ -n "$NLB_ARN" ]; then
  NLB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$NLB_ARN" \
    --region "$REGION" \
    --query 'LoadBalancers[0].DNSName' \
    --output text)
  echo "✅ NLB DNS: $NLB_DNS"
  echo "   Port: 5439 (Redshift)"
else
  echo "❌ NLB not found"
fi

# 2. Show Target Group
echo -e "\n📍 STEP 2: TARGET GROUP CONFIGURATION"
echo "-----------------------------------------"
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --names "${PROJECT_NAME}-consumers" \
  --region "$REGION" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null)

if [ -n "$TARGET_GROUP_ARN" ]; then
  aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --region "$REGION" \
    --query 'TargetGroups[0].{Name:TargetGroupName,Type:TargetType,Protocol:Protocol,Port:Port}' \
    --output table
fi

# 3. Show Consumer Workgroups
echo -e "\n📍 STEP 3: REDSHIFT SERVERLESS WORKGROUPS"
echo "-----------------------------------------"
WORKGROUPS=$(aws redshift-serverless list-workgroups \
  --region "$REGION" \
  --query "workgroups[?contains(workgroupName, '${PROJECT_NAME}-consumer-wg')].workgroupName" \
  --output text)

echo "Found $(echo $WORKGROUPS | wc -w) consumer workgroups:"
for WG in $WORKGROUPS; do
  echo "  • $WG"
done

# 4. Map Workgroups to VPC Endpoints
echo -e "\n📍 STEP 4: VPC ENDPOINTS (One per Workgroup)"
echo "-----------------------------------------"
for WORKGROUP in $WORKGROUPS; do
  echo -e "\n🔹 Workgroup: $WORKGROUP"
  
  # Get VPC endpoint details
  ENDPOINT_INFO=$(aws redshift-serverless get-workgroup \
    --workgroup-name "$WORKGROUP" \
    --region "$REGION" \
    --query 'workgroup.endpoint' \
    --output json 2>/dev/null)
  
  if [ -n "$ENDPOINT_INFO" ]; then
    ENDPOINT_ADDRESS=$(echo "$ENDPOINT_INFO" | jq -r '.address // "N/A"')
    VPC_ENDPOINT_ID=$(echo "$ENDPOINT_INFO" | jq -r '.vpcEndpoints[0].vpcEndpointId // "N/A"')
    
    echo "   Endpoint DNS: $ENDPOINT_ADDRESS"
    echo "   VPC Endpoint ID: $VPC_ENDPOINT_ID"
    
    # Get ENIs for this VPC endpoint
    if [ "$VPC_ENDPOINT_ID" != "N/A" ] && [ "$VPC_ENDPOINT_ID" != "null" ]; then
      ENI_IDS=$(aws ec2 describe-vpc-endpoints \
        --vpc-endpoint-ids "$VPC_ENDPOINT_ID" \
        --region "$REGION" \
        --query 'VpcEndpoints[0].NetworkInterfaceIds' \
        --output json 2>/dev/null | jq -r '.[]' 2>/dev/null)
      
      if [ -n "$ENI_IDS" ]; then
        echo "   ENIs and IPs:"
        for ENI_ID in $ENI_IDS; do
          ENI_INFO=$(aws ec2 describe-network-interfaces \
            --network-interface-ids "$ENI_ID" \
            --region "$REGION" \
            --query 'NetworkInterfaces[0].{IP:PrivateIpAddress,Subnet:SubnetId,AZ:AvailabilityZone}' \
            --output json 2>/dev/null)
          
          if [ -n "$ENI_INFO" ]; then
            IP=$(echo "$ENI_INFO" | jq -r '.IP')
            SUBNET=$(echo "$ENI_INFO" | jq -r '.Subnet')
            AZ=$(echo "$ENI_INFO" | jq -r '.AZ')
            echo "     - IP: $IP (AZ: $AZ, Subnet: $SUBNET)"
          fi
        done
      fi
    fi
  fi
done

# 5. Show Registered Targets
echo -e "\n📍 STEP 5: NLB REGISTERED TARGETS"
echo "-----------------------------------------"
echo "Target IPs registered in NLB:"
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# 6. Summary
echo -e "\n📍 STEP 6: ARCHITECTURE SUMMARY"
echo "-----------------------------------------"
TOTAL_TARGETS=$(aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'length(TargetHealthDescriptions)' \
  --output text)

HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$REGION" \
  --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
  --output text)

NUM_WORKGROUPS=$(echo $WORKGROUPS | wc -w)
NUM_AZS=$(aws ec2 describe-availability-zones \
  --region "$REGION" \
  --query 'length(AvailabilityZones[?State==`available`])' \
  --output text)

echo "✅ Architecture Formula:"
echo "   $NUM_WORKGROUPS workgroups × 3 AZs = $TOTAL_TARGETS target IPs"
echo ""
echo "📊 Health Status:"
echo "   Total Targets: $TOTAL_TARGETS"
echo "   Healthy: $HEALTHY_TARGETS"
echo "   Formula Check: $([ "$TOTAL_TARGETS" -eq "$((NUM_WORKGROUPS * 3))" ] && echo "✅ CORRECT" || echo "❌ MISMATCH")"

echo -e "\n🎯 KEY INSIGHT:"
echo "Each Redshift Serverless workgroup creates a VPC endpoint that spawns"
echo "ENIs across multiple AZs for high availability. The NLB targets these"
echo "individual ENI IPs, not the workgroup DNS names."

echo -e "\n📌 TO TEST LOAD BALANCING:"
echo "psql -h $NLB_DNS -p 5439 -U admin -d dev -c 'SELECT current_namespace;'"
echo "(Run multiple times to see different namespace IDs = different workgroups)"