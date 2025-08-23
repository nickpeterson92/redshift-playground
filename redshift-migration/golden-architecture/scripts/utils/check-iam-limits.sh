#!/bin/bash

# Check IAM permissions, SCPs, and organizational limits

echo "=== Checking IAM Permissions and Organizational Limits ==="
echo ""

# Get current identity
echo "1. Current AWS Identity:"
aws sts get-caller-identity --output json | jq '.'

echo ""
echo "2. Checking Service Control Policies (SCPs):"
# Try to list organization policies (may fail if not org admin)
aws organizations list-policies-for-target \
    --target-id $(aws sts get-caller-identity --query Account --output text) \
    --filter SERVICE_CONTROL_POLICY \
    --output json 2>/dev/null | jq '.' || echo "   Unable to check SCPs (need org permissions)"

echo ""
echo "3. Checking Permission Boundaries:"
# Get current user/role
IDENTITY_TYPE=$(aws sts get-caller-identity --query Arn --output text | cut -d: -f6 | cut -d/ -f1)
IDENTITY_NAME=$(aws sts get-caller-identity --query Arn --output text | cut -d/ -f2)

if [ "$IDENTITY_TYPE" = "user" ]; then
    echo "   Checking user permission boundary..."
    aws iam get-user --user-name "$IDENTITY_NAME" \
        --query 'User.PermissionsBoundary' --output json 2>/dev/null || echo "   No permission boundary or unable to check"
elif [ "$IDENTITY_TYPE" = "assumed-role" ]; then
    ROLE_NAME=$(echo "$IDENTITY_NAME" | cut -d/ -f2)
    echo "   Checking role permission boundary..."
    aws iam get-role --role-name "$ROLE_NAME" \
        --query 'Role.PermissionsBoundary' --output json 2>/dev/null || echo "   No permission boundary or unable to check"
fi

echo ""
echo "4. Checking Redshift-specific Permissions:"
# Try to simulate creating a workgroup
aws iam simulate-principal-policy \
    --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
    --action-names redshift-serverless:CreateWorkgroup \
    --resource-arns "*" \
    --output json 2>/dev/null | jq '.EvaluationResults[0]' || echo "   Unable to simulate (need IAM permissions)"

echo ""
echo "5. Checking Service Quotas Permissions:"
# Check if we can even see quotas
aws service-quotas list-service-quotas \
    --service-code redshift-serverless \
    --max-items 1 &>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✓ Can access service quotas"
    
    # Try to get specific quotas
    echo ""
    echo "   Redshift Serverless Quotas:"
    
    # Workgroups per account
    aws service-quotas get-service-quota \
        --service-code redshift-serverless \
        --quota-code L-BBE2F907 \
        --query 'Quota.{Name:QuotaName,Value:Value,Adjustable:Adjustable}' \
        --output json 2>/dev/null | jq '.' || echo "   - Workgroups quota: Unable to retrieve"
    
    # RPU hours
    aws service-quotas get-service-quota \
        --service-code redshift-serverless \
        --quota-code L-4793E831 \
        --query 'Quota.{Name:QuotaName,Value:Value,Adjustable:Adjustable}' \
        --output json 2>/dev/null | jq '.' || echo "   - RPU hours quota: Unable to retrieve"
else
    echo "   ✗ Cannot access service quotas (may be restricted by IAM)"
fi

echo ""
echo "6. Checking for Tag-based Restrictions:"
# Check if there are tag requirements
aws redshift-serverless list-workgroups \
    --query 'workgroups[0].tags' \
    --output json | jq '.' || echo "   No workgroups to check"

echo ""
echo "7. Checking Resource Tagging Policies:"
aws organizations describe-effective-policy \
    --policy-type TAG_POLICY \
    --target-id $(aws sts get-caller-identity --query Account --output text) \
    --output json 2>/dev/null | jq '.EffectivePolicy' || echo "   No tag policies or unable to check"

echo ""
echo "8. Checking for CloudTrail Denied Events:"
echo "   Recent access denied events for Redshift:"
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=CreateWorkgroup \
    --max-items 10 \
    --query 'Events[?ErrorCode==`AccessDenied`].[EventTime,ErrorCode,ErrorMessage]' \
    --output table 2>/dev/null || echo "   Unable to check CloudTrail"

echo ""
echo "9. Common Organizational Limits:"
echo "   - Max workgroups might be limited by organization policy"
echo "   - Certain regions might be restricted"
echo "   - Resource creation might require specific tags"
echo "   - Cost controls might limit RPU allocation"

echo ""
echo "10. Testing Actual Permissions:"
echo "   Attempting a dry-run workgroup creation..."

# Try to create a test workgroup (will fail but shows if permission denied)
TEST_WG="test-permission-check-$(date +%s)"
aws redshift-serverless create-workgroup \
    --workgroup-name "$TEST_WG" \
    --namespace-name "test-ns" \
    --base-capacity 32 \
    --no-cli-pager \
    --output json 2>&1 | head -20 | grep -E "(AccessDenied|Limit|Quota|Maximum)" || echo "   Check passed (error was not permission-related)"

echo ""
echo "=== Summary ==="
echo "If you see AccessDenied errors or quota limits above, your organization"
echo "may have restrictions. Contact your AWS administrator to:"
echo "1. Check Service Control Policies (SCPs)"
echo "2. Review Permission Boundaries"
echo "3. Request quota increases"
echo "4. Verify tag compliance requirements"