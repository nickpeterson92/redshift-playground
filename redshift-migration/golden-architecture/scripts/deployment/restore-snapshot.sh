#!/bin/bash
# Restore snapshot to Redshift Serverless producer namespace
# Usage: ./restore-snapshot.sh <namespace-name> <workgroup-name> <snapshot-name> <region>

set -e

# Arguments
NAMESPACE_NAME="$1"
WORKGROUP_NAME="$2"
SNAPSHOT_NAME="$3"
REGION="${4:-us-west-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}SNAPSHOT RESTORATION${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo "Namespace: $NAMESPACE_NAME"
echo "Workgroup: $WORKGROUP_NAME"
echo "Snapshot: $SNAPSHOT_NAME"
echo "Region: $REGION"
echo ""

# Check current namespace status
echo "Checking namespace status..."
CURRENT_STATUS=$(aws redshift-serverless get-namespace \
  --namespace-name "$NAMESPACE_NAME" \
  --query 'namespace.status' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if [ "$CURRENT_STATUS" = "NOT_FOUND" ]; then
  echo -e "${RED}Error: Namespace $NAMESPACE_NAME not found${NC}"
  exit 1
fi

echo "Current status: $CURRENT_STATUS"

# Get the cluster identifier from the snapshot
echo "Looking up snapshot details..."
CLUSTER_ID=$(aws redshift describe-cluster-snapshots \
  --snapshot-identifier "$SNAPSHOT_NAME" \
  --query 'Snapshots[0].ClusterIdentifier' \
  --output text \
  --region "$REGION" 2>/dev/null || echo "")

if [ -z "$CLUSTER_ID" ]; then
  echo -e "${RED}Error: Snapshot $SNAPSHOT_NAME not found${NC}"
  exit 1
fi

# Build the snapshot ARN
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNAPSHOT_ARN="arn:aws:redshift:${REGION}:${ACCOUNT_ID}:snapshot:${CLUSTER_ID}/${SNAPSHOT_NAME}"
echo "Snapshot ARN: $SNAPSHOT_ARN"

# Execute the restore
echo ""
echo "Starting snapshot restore..."
RESTORE_OUTPUT=$(aws redshift-serverless restore-from-snapshot \
  --namespace-name "$NAMESPACE_NAME" \
  --workgroup-name "$WORKGROUP_NAME" \
  --snapshot-arn "$SNAPSHOT_ARN" \
  --region "$REGION" 2>&1)

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Restore command executed successfully${NC}"
else
  echo -e "${RED}✗ Restore command failed:${NC}"
  echo "$RESTORE_OUTPUT"
  exit 1
fi

# Monitor the restore progress
echo ""
echo "Monitoring restore progress..."
MAX_ATTEMPTS=60  # 30 minutes max (30 seconds * 60)
ATTEMPT=0
RESTORE_STARTED=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  STATUS=$(aws redshift-serverless get-namespace \
    --namespace-name "$NAMESPACE_NAME" \
    --query 'namespace.status' \
    --output text \
    --region "$REGION" 2>/dev/null)
  
  if [ "$STATUS" = "MODIFYING" ]; then
    if [ "$RESTORE_STARTED" = false ]; then
      echo -e "${YELLOW}⟳ Namespace is MODIFYING - restore in progress...${NC}"
      RESTORE_STARTED=true
    else
      echo -n "."
    fi
  elif [ "$RESTORE_STARTED" = true ] && [ "$STATUS" = "AVAILABLE" ]; then
    echo ""
    echo -e "${GREEN}✓ Restore complete! Namespace is AVAILABLE${NC}"
    exit 0
  fi
  
  sleep 30
  ATTEMPT=$((ATTEMPT + 1))
done

echo ""
echo -e "${RED}✗ Restore timed out after 30 minutes${NC}"
exit 1