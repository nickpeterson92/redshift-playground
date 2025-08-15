#!/bin/bash

# Monitor Redshift Serverless Deployment in Real-Time
# Shows status of all workgroups and helps identify issues during deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REFRESH_INTERVAL=${1:-10}  # Default 10 seconds
DEPLOYMENT_TIMEOUT=1800     # 30 minutes

echo "========================================="
echo "Redshift Serverless Deployment Monitor"
echo "========================================="
echo "Refresh interval: ${REFRESH_INTERVAL}s"
echo "Press Ctrl+C to exit"
echo ""

start_time=$(date +%s)

# Function to get workgroup status with details
get_workgroup_details() {
    local wg_name=$1
    local details=$(aws redshift-serverless get-workgroup --workgroup-name "$wg_name" 2>/dev/null || echo "{}")
    
    if [ "$details" == "{}" ]; then
        echo "NOT_FOUND|N/A|N/A|N/A"
        return
    fi
    
    local status=$(echo "$details" | jq -r '.workgroup.status // "UNKNOWN"')
    local namespace=$(echo "$details" | jq -r '.workgroup.namespaceName // "N/A"')
    local rpus=$(echo "$details" | jq -r '.workgroup.baseCapacity // "N/A"')
    local endpoint_status="N/A"
    
    # Check for VPC endpoint
    local endpoint_id=$(echo "$details" | jq -r '.workgroup.endpoint.vpcEndpointId // empty')
    if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "null" ]; then
        local vpc_endpoint=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$endpoint_id" 2>/dev/null || echo "{}")
        if [ "$vpc_endpoint" != "{}" ]; then
            endpoint_status=$(echo "$vpc_endpoint" | jq -r '.VpcEndpoints[0].State // "N/A"')
        fi
    fi
    
    echo "${status}|${namespace}|${rpus}|${endpoint_status}"
}

# Function to display status with color coding
display_status() {
    local status=$1
    case $status in
        "AVAILABLE")
            echo -e "${GREEN}✅ AVAILABLE${NC}"
            ;;
        "CREATING")
            echo -e "${BLUE}🔄 CREATING${NC}"
            ;;
        "MODIFYING")
            echo -e "${YELLOW}⚙️  MODIFYING${NC}"
            ;;
        "DELETING")
            echo -e "${RED}🗑️  DELETING${NC}"
            ;;
        "NOT_FOUND")
            echo -e "${RED}❌ NOT FOUND${NC}"
            ;;
        *)
            echo -e "${RED}❓ $status${NC}"
            ;;
    esac
}

# Function to check for issues
check_for_issues() {
    local all_workgroups=$1
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    
    # Count workgroups in each state
    local creating_count=0
    local modifying_count=0
    local available_count=0
    local error_count=0
    
    while IFS='|' read -r name status namespace rpus endpoint; do
        case $status in
            "CREATING") ((creating_count++)) ;;
            "MODIFYING") ((modifying_count++)) ;;
            "AVAILABLE") ((available_count++)) ;;
            "ERROR"|"UNKNOWN"|"NOT_FOUND") ((error_count++)) ;;
        esac
    done <<< "$all_workgroups"
    
    # Display warnings
    if [ $modifying_count -gt 0 ] && [ $elapsed -gt 600 ]; then
        echo -e "\n${YELLOW}⚠️  Warning: $modifying_count workgroup(s) stuck in MODIFYING state for >10 minutes${NC}"
    fi
    
    if [ $error_count -gt 0 ]; then
        echo -e "\n${RED}❌ Error: $error_count workgroup(s) in error state${NC}"
    fi
    
    # Check subnet capacity
    local subnet_check=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=*redshift*" \
        --query 'Subnets[?AvailableIpAddressCount<`32`].[SubnetId,AvailableIpAddressCount]' \
        --output text 2>/dev/null)
    
    if [ -n "$subnet_check" ]; then
        echo -e "\n${YELLOW}⚠️  Warning: Low IP availability in subnets:${NC}"
        echo "$subnet_check"
    fi
}

# Main monitoring loop
iteration=0
while true; do
    clear
    iteration=$((iteration + 1))
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    elapsed_min=$((elapsed / 60))
    elapsed_sec=$((elapsed % 60))
    
    echo "========================================="
    echo "Redshift Serverless Deployment Monitor"
    echo "========================================="
    echo "Iteration: $iteration | Elapsed: ${elapsed_min}m ${elapsed_sec}s | $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
    echo ""
    
    # Get all workgroups
    echo -e "${BLUE}Fetching workgroup status...${NC}"
    all_workgroups=$(aws redshift-serverless list-workgroups --query 'workgroups[*].workgroupName' --output text)
    
    if [ -z "$all_workgroups" ]; then
        echo -e "${YELLOW}No workgroups found${NC}"
    else
        # Display header
        printf "%-30s %-15s %-20s %-10s %-15s\n" "Workgroup" "Status" "Namespace" "RPUs" "VPC Endpoint"
        printf "%-30s %-15s %-20s %-10s %-15s\n" "---------" "------" "---------" "----" "------------"
        
        # Collect all workgroup details
        all_details=""
        for wg in $all_workgroups; do
            details=$(get_workgroup_details "$wg")
            all_details="${all_details}${wg}|${details}\n"
        done
        
        # Display workgroup details
        echo -e "$all_details" | while IFS='|' read -r name status namespace rpus endpoint; do
            if [ -n "$name" ]; then
                printf "%-30s " "$name"
                display_status "$status"
                printf " %-20s %-10s %-15s\n" "$namespace" "$rpus" "$endpoint"
            fi
        done
        
        # Check for issues
        check_for_issues "$all_details"
    fi
    
    # Show namespace status
    echo -e "\n${BLUE}Namespace Status:${NC}"
    aws redshift-serverless list-namespaces --query 'namespaces[*].[namespaceName,status]' --output table
    
    # Show CloudWatch logs if available (more useful than CloudTrail)
    echo -e "\n${BLUE}Recent Activity (CloudWatch Logs):${NC}"
    
    # Try to get recent connection logs
    log_groups=$(aws logs describe-log-groups --log-group-name-prefix "/aws/redshift-serverless" --query 'logGroups[*].logGroupName' --output text 2>/dev/null)
    
    if [ -n "$log_groups" ]; then
        echo "Log groups found:"
        echo "$log_groups" | tr '\t' '\n' | head -5
        echo "(Use CloudWatch Insights for detailed analysis)"
    else
        echo "No CloudWatch log groups found (this is normal)"
    fi
    
    # More useful: Show recent workgroup events
    echo -e "\n${BLUE}Recent Workgroup Changes:${NC}"
    for wg in $all_workgroups; do
        created=$(aws redshiftserverless get-workgroup --workgroup-name "$wg" --query 'workgroup.createdAt' --output text 2>/dev/null || echo "N/A")
        if [ "$created" != "N/A" ] && [ "$created" != "None" ]; then
            # Calculate age
            if [[ "$OSTYPE" == "darwin"* ]]; then
                created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created%%.*}" +%s 2>/dev/null || echo "0")
            else
                created_epoch=$(date -d "$created" +%s 2>/dev/null || echo "0")
            fi
            
            if [ "$created_epoch" -gt 0 ]; then
                age=$(( (current_time - created_epoch) / 60 ))
                if [ $age -lt 60 ]; then
                    echo "  $wg: Created ${age} minutes ago"
                fi
            fi
        fi
    done
    
    # Show help at bottom
    echo ""
    echo "========================================="
    echo "Tips:"
    echo "• Workgroups typically take 3-5 minutes to create"
    echo "• MODIFYING state >10 minutes may indicate an issue"
    echo "• Run './diagnose-workgroup.sh <name>' for detailed diagnostics"
    echo "• Press Ctrl+C to exit"
    
    # Check for timeout
    if [ $elapsed -gt $DEPLOYMENT_TIMEOUT ]; then
        echo -e "\n${RED}❌ Deployment timeout reached (30 minutes)${NC}"
        echo "Consider checking AWS service health or contacting support"
        exit 1
    fi
    
    # Wait before next refresh
    sleep $REFRESH_INTERVAL
done