#!/bin/bash

# Check AWS limits and resource availability for Redshift Serverless

echo "=== Checking AWS Limits and Resources ==="
echo ""

# Check Redshift Serverless quotas
echo "1. Redshift Serverless Service Quotas:"
aws service-quotas list-service-quotas \
    --service-code redshift-serverless \
    --query 'Quotas[?contains(QuotaName, `workgroup`) || contains(QuotaName, `namespace`)].{Name:QuotaName,Value:Value,Used:UsageMetric.MetricStatisticRecommendation}' \
    --output table 2>/dev/null || echo "Unable to retrieve quotas"

echo ""
echo "2. Current Redshift Serverless Resources:"
# Count workgroups
WORKGROUP_COUNT=$(aws redshift-serverless list-workgroups --query 'length(workgroups)' --output text)
echo "   Total Workgroups: $WORKGROUP_COUNT"

# Count by status
echo "   Workgroups by status:"
aws redshift-serverless list-workgroups \
    --query 'workgroups[*].status' \
    --output text | tr '\t' '\n' | sort | uniq -c

echo ""
echo "3. RPU (Redshift Processing Units) Usage:"
aws redshift-serverless list-workgroups \
    --query 'workgroups[*].[workgroupName,baseCapacity,maxCapacity,status]' \
    --output table

echo ""
echo "4. VPC Subnet IP Availability:"
# Get VPC and subnets from first workgroup
VPC_ID=$(aws redshift-serverless list-workgroups \
    --query 'workgroups[0].subnetIds[0]' \
    --output text | xargs -I {} aws ec2 describe-subnets \
    --subnet-ids {} \
    --query 'Subnets[0].VpcId' \
    --output text 2>/dev/null)

if [ -n "$VPC_ID" ]; then
    echo "   VPC: $VPC_ID"
    aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].[SubnetId,AvailableIpAddressCount,CidrBlock]' \
        --output table
fi

echo ""
echo "5. Account-level EC2 Limits (affects VPC Endpoints):"
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-29D0E15C \
    --query 'Quota.{Name:QuotaName,Value:Value}' \
    --output json 2>/dev/null || echo "VPC Endpoints per Region: (unable to retrieve)"

echo ""
echo "6. Checking for stuck resources:"
# Check for workgroups stuck in transitional states
MODIFYING=$(aws redshift-serverless list-workgroups \
    --query "workgroups[?status=='MODIFYING'].workgroupName" \
    --output text)

if [ -n "$MODIFYING" ]; then
    echo "   ⚠️  Workgroups stuck in MODIFYING state:"
    for WG in $MODIFYING; do
        echo "      - $WG"
        # Try to get more details
        aws redshift-serverless get-workgroup \
            --workgroup-name "$WG" \
            --query 'workgroup.{Status:status,ConfigParams:configParameters}' \
            --output json 2>/dev/null | jq '.' || true
    done
else
    echo "   ✓ No workgroups in MODIFYING state"
fi

echo ""
echo "7. Common Limits:"
echo "   - Max workgroups per account: Usually 10-20 (soft limit)"
echo "   - Max RPU per workgroup: 1024"
echo "   - Max total RPU per account: Varies by region"
echo "   - VPC Endpoints per VPC: 255"
echo "   - Network interfaces per subnet: Depends on subnet size"

echo ""
echo "8. Recommendations:"
if [ "$WORKGROUP_COUNT" -ge 10 ]; then
    echo "   ⚠️  You have $WORKGROUP_COUNT workgroups. Consider requesting a quota increase."
fi

# Check if sequential locking is even needed
echo ""
echo "9. Testing Concurrent Creation Capability:"
echo "   AWS may have fixed the concurrent creation issue."
echo "   The sequential locking scripts might no longer be necessary."
echo "   Consider testing with direct Terraform deployment (no locking scripts)."