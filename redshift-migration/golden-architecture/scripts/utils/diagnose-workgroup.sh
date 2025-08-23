#!/bin/bash

# Diagnose Redshift Serverless Workgroup Issues
# This script helps identify why workgroups get stuck in "modifying" state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Redshift Serverless Workgroup Diagnostics"
echo "========================================="

# Function to check workgroup status
check_workgroup_status() {
    local workgroup_name=$1
    echo -e "\n${YELLOW}Checking workgroup: $workgroup_name${NC}"
    
    # Get workgroup details
    workgroup_info=$(aws redshiftserverless get-workgroup --workgroup-name "$workgroup_name" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$workgroup_info" == "NOT_FOUND" ]; then
        echo -e "${RED}Workgroup $workgroup_name not found${NC}"
        return 1
    fi
    
    # Extract status
    status=$(echo "$workgroup_info" | jq -r '.workgroup.status')
    echo "Status: $status"
    
    # Check creation/modification time
    created=$(echo "$workgroup_info" | jq -r '.workgroup.createdAt')
    echo "Created: $created"
    
    # Check if CloudWatch logs are configured
    namespace=$(echo "$workgroup_info" | jq -r '.workgroup.namespaceName')
    if [ "$namespace" != "null" ]; then
        namespace_info=$(aws redshiftserverless get-namespace --namespace-name "$namespace" 2>/dev/null)
        if [ -n "$namespace_info" ]; then
            log_exports=$(echo "$namespace_info" | jq -r '.namespace.logExports[]' 2>/dev/null)
            if [ -n "$log_exports" ]; then
                echo "CloudWatch Logs enabled: $log_exports"
            else
                echo "CloudWatch Logs: Not configured"
            fi
        fi
    fi
    
    # Check namespace association
    namespace=$(echo "$workgroup_info" | jq -r '.workgroup.namespaceName')
    echo "Namespace: $namespace"
    
    # Check if status is stuck
    if [ "$status" == "MODIFYING" ]; then
        echo -e "${YELLOW}⚠️  Workgroup is in MODIFYING state${NC}"
        
        # Calculate how long it's been modifying
        created_epoch=$(date -d "$created" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$created" +%s 2>/dev/null || echo "0")
        current_epoch=$(date +%s)
        duration=$((current_epoch - created_epoch))
        duration_min=$((duration / 60))
        
        if [ $duration_min -gt 10 ]; then
            echo -e "${RED}❌ Workgroup has been modifying for ${duration_min} minutes (may be stuck)${NC}"
        else
            echo -e "${YELLOW}⏳ Workgroup has been modifying for ${duration_min} minutes (still within normal range)${NC}"
        fi
    elif [ "$status" == "AVAILABLE" ]; then
        echo -e "${GREEN}✅ Workgroup is available${NC}"
    else
        echo -e "${RED}❌ Workgroup is in unexpected state: $status${NC}"
    fi
    
    # Check namespace status
    echo -e "\n${YELLOW}Checking associated namespace: $namespace${NC}"
    namespace_info=$(aws redshiftserverless get-namespace --namespace-name "$namespace" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$namespace_info" != "NOT_FOUND" ]; then
        namespace_status=$(echo "$namespace_info" | jq -r '.namespace.status')
        echo "Namespace Status: $namespace_status"
        
        if [ "$namespace_status" != "AVAILABLE" ]; then
            echo -e "${YELLOW}⚠️  Namespace is not available (status: $namespace_status)${NC}"
        fi
    fi
    
    echo "---"
}

# Function to check VPC endpoints
check_vpc_endpoints() {
    local workgroup_name=$1
    echo -e "\n${YELLOW}Checking VPC endpoints for workgroup: $workgroup_name${NC}"
    
    # Get workgroup endpoint
    endpoint_info=$(aws redshiftserverless get-workgroup --workgroup-name "$workgroup_name" 2>/dev/null | jq -r '.workgroup.endpoint')
    
    if [ "$endpoint_info" != "null" ] && [ -n "$endpoint_info" ]; then
        endpoint_id=$(echo "$endpoint_info" | jq -r '.vpcEndpointId // empty')
        if [ -n "$endpoint_id" ]; then
            echo "VPC Endpoint ID: $endpoint_id"
            
            # Check VPC endpoint status
            vpc_endpoint=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$endpoint_id" 2>/dev/null || echo "NOT_FOUND")
            if [ "$vpc_endpoint" != "NOT_FOUND" ]; then
                vpc_status=$(echo "$vpc_endpoint" | jq -r '.VpcEndpoints[0].State')
                echo "VPC Endpoint Status: $vpc_status"
                
                if [ "$vpc_status" == "pending" ]; then
                    echo -e "${YELLOW}⚠️  VPC endpoint is still pending${NC}"
                elif [ "$vpc_status" == "available" ]; then
                    echo -e "${GREEN}✅ VPC endpoint is available${NC}"
                else
                    echo -e "${RED}❌ VPC endpoint is in unexpected state: $vpc_status${NC}"
                fi
            fi
        else
            echo "No VPC endpoint associated yet"
        fi
    else
        echo "No endpoint information available"
    fi
}

# Function to check subnet capacity
check_subnet_capacity() {
    echo -e "\n${YELLOW}Checking subnet IP availability${NC}"
    
    # Get all serverless workgroups
    workgroups=$(aws redshiftserverless list-workgroups --query 'workgroups[*].[workgroupName,subnetIds[0]]' --output text)
    
    # Count unique subnets
    subnets=$(echo "$workgroups" | awk '{print $2}' | sort -u)
    
    for subnet in $subnets; do
        if [ "$subnet" != "None" ] && [ -n "$subnet" ]; then
            echo -e "\nSubnet: $subnet"
            
            # Get subnet details
            subnet_info=$(aws ec2 describe-subnets --subnet-ids "$subnet" 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$subnet_info" != "NOT_FOUND" ]; then
                available_ips=$(echo "$subnet_info" | jq -r '.Subnets[0].AvailableIpAddressCount')
                cidr=$(echo "$subnet_info" | jq -r '.Subnets[0].CidrBlock')
                
                echo "CIDR: $cidr"
                echo "Available IPs: $available_ips"
                
                if [ "$available_ips" -lt 32 ]; then
                    echo -e "${RED}❌ Low IP availability (less than 32 IPs)${NC}"
                elif [ "$available_ips" -lt 64 ]; then
                    echo -e "${YELLOW}⚠️  Moderate IP availability${NC}"
                else
                    echo -e "${GREEN}✅ Sufficient IP availability${NC}"
                fi
            fi
        fi
    done
}

# Function to check for resource limits
check_resource_limits() {
    echo -e "\n${YELLOW}Checking resource counts${NC}"
    
    # Count workgroups
    workgroup_count=$(aws redshiftserverless list-workgroups --query 'length(workgroups)' --output text)
    echo "Total workgroups: $workgroup_count"
    
    # Count namespaces
    namespace_count=$(aws redshiftserverless list-namespaces --query 'length(namespaces)' --output text)
    echo "Total namespaces: $namespace_count"
    
    # Check for common limits
    if [ "$workgroup_count" -ge 10 ]; then
        echo -e "${YELLOW}⚠️  High number of workgroups (may be approaching limits)${NC}"
    fi
    
    # Check RPU usage
    total_rpus=0
    workgroups=$(aws redshiftserverless list-workgroups --query 'workgroups[*].[workgroupName,baseCapacity]' --output text)
    while IFS=$'\t' read -r name capacity; do
        if [ -n "$capacity" ] && [ "$capacity" != "None" ]; then
            total_rpus=$((total_rpus + capacity))
        fi
    done <<< "$workgroups"
    
    echo "Total RPUs allocated: $total_rpus"
    
    if [ "$total_rpus" -gt 512 ]; then
        echo -e "${YELLOW}⚠️  High RPU allocation (check account limits)${NC}"
    fi
}

# Main execution
echo -e "\n${GREEN}Starting diagnostics...${NC}"

# Check if specific workgroup provided
if [ -n "$1" ]; then
    check_workgroup_status "$1"
    check_vpc_endpoints "$1"
else
    # List all workgroups
    echo -e "\n${YELLOW}Listing all workgroups:${NC}"
    aws redshiftserverless list-workgroups --query 'workgroups[*].[workgroupName,status]' --output table
    
    # Check each workgroup
    workgroups=$(aws redshiftserverless list-workgroups --query 'workgroups[*].workgroupName' --output text)
    for wg in $workgroups; do
        check_workgroup_status "$wg"
    done
fi

# Always check subnet capacity and limits
check_subnet_capacity
check_resource_limits

echo -e "\n${GREEN}Diagnostics complete!${NC}"
echo ""
echo "Common solutions for stuck workgroups:"
echo "1. Wait 15-20 minutes - AWS can be slow"
echo "2. Check subnet IP availability"
echo "3. Verify no other operations are pending"
echo "4. Try deleting and recreating if stuck > 30 minutes"
echo "5. Check AWS service health dashboard"
echo "6. Contact AWS support if issue persists"