#!/bin/bash
# Script to get private IPs from Redshift endpoint access
# Required because Terraform provider doesn't expose these yet

set -e

# Parse input JSON
eval "$(jq -r '@sh "ENDPOINT_NAME=\(.endpoint_name) REGION=\(.region)"')"

# Get the endpoint details
ENDPOINT_JSON=$(aws redshift-serverless get-endpoint-access \
  --endpoint-name "$ENDPOINT_NAME" \
  --region "$REGION" 2>/dev/null || echo '{}')

# Extract private IPs
IPS=$(echo "$ENDPOINT_JSON" | jq -r '.endpoint.vpcEndpoint.networkInterfaces[].privateIpAddress' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Output as JSON
if [ -z "$IPS" ]; then
  echo '{"ips":""}' 
else
  echo "{\"ips\":\"$IPS\"}"
fi