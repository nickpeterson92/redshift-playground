#!/usr/bin/env python3
"""
Test NLB load balancing by running tests directly on EC2 instances.
This script copies a test script to each EC2 instance and runs it there.
"""

import json
import subprocess
import sys
import os
from collections import defaultdict
from typing import List, Dict, Tuple

# Colors for output
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
NC = '\033[0m'  # No Color

def run_command(cmd: List[str], capture=True, timeout=30) -> Tuple[int, str, str]:
    """Run a command and return (returncode, stdout, stderr)"""
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "Command timed out"
    except Exception as e:
        return 1, "", str(e)

def get_terraform_output(output_name: str) -> any:
    """Get a terraform output value"""
    code, stdout, stderr = run_command(["terraform", "output", "-json", output_name])
    if code == 0:
        try:
            return json.loads(stdout)
        except:
            return None
    return None

def create_test_script(nlb_endpoint: str, password: str) -> str:
    """Create the test script that will run on EC2 instances"""
    return f'''#!/usr/bin/env python3
import psycopg2
import sys
from collections import defaultdict

def test_connections(nlb_endpoint, password, num_tests=20):
    consumer_counts = defaultdict(int)
    successful = 0
    
    for i in range(num_tests):
        try:
            conn = psycopg2.connect(
                host=nlb_endpoint,
                port=5439,
                database="consumer_db",
                user="admin",
                password=password,
                connect_timeout=10
            )
            
            cur = conn.cursor()
            
            # Try to identify which consumer we connected to
            try:
                cur.execute("SELECT current_namespace")
                result = cur.fetchone()
                if result and result[0]:
                    # Use the namespace ID as the consumer identifier
                    namespace = result[0]
                    consumer = namespace  # Use full namespace for identification
                else:
                    consumer = "unknown"
            except Exception as e:
                # Fallback
                consumer = "error"
            
            consumer_counts[consumer] += 1
            successful += 1
            print(f"Connection {{i+1}}: {{consumer}}")
            
            cur.close()
            conn.close()
            
        except Exception as e:
            print(f"Connection {{i+1}}: Failed - {{str(e)[:100]}}")
    
    print(f"\\nResults: {{successful}}/{{num_tests}} successful")
    for consumer, count in consumer_counts.items():
        print(f"{{consumer}}: {{count}}")
    
    return dict(consumer_counts)

if __name__ == "__main__":
    nlb_endpoint = "{nlb_endpoint}"
    password = "{password}"
    test_connections(nlb_endpoint, password)
'''

def test_from_instance(instance_ip: str, instance_num: int, nlb_endpoint: str, 
                       password: str) -> Dict[str, int]:
    """Copy test script to instance and run it"""
    print(f"\n{CYAN}Testing from Instance {instance_num} ({instance_ip})...{NC}")
    
    # Create the test script
    test_script = create_test_script(nlb_endpoint, password)
    
    # Write it to a temp file
    with open('/tmp/ec2_test.py', 'w') as f:
        f.write(test_script)
    
    # Copy script to EC2 instance
    scp_cmd = [
        "scp",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        "-i", "./test-instance.pem",
        "/tmp/ec2_test.py",
        f"ec2-user@{instance_ip}:/tmp/test.py"
    ]
    
    code, stdout, stderr = run_command(scp_cmd, timeout=30)
    if code != 0:
        print(f"{RED}  ❌ Failed to copy script: {stderr}{NC}")
        return {}
    
    # Install psycopg2 on the instance if needed
    # First check if it's already installed
    ssh_check = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        "-i", "./test-instance.pem",
        f"ec2-user@{instance_ip}",
        "python3 -c 'import psycopg2' 2>/dev/null && echo 'installed' || echo 'missing'"
    ]
    code, stdout, stderr = run_command(ssh_check, timeout=30)
    
    if "missing" in stdout:
        print(f"  Installing psycopg2-binary...")
        ssh_install = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
            "-i", "./test-instance.pem",
            f"ec2-user@{instance_ip}",
            "sudo yum install -y python3-pip 2>/dev/null && sudo pip3 install psycopg2-binary"
        ]
        code, stdout, stderr = run_command(ssh_install, timeout=120)
        if code != 0:
            print(f"{YELLOW}  ⚠ Package installation may have failed, trying anyway...{NC}")
    
    # Run the test script
    ssh_cmd = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        "-i", "./test-instance.pem",
        f"ec2-user@{instance_ip}",
        "python3 /tmp/test.py"
    ]
    
    code, stdout, stderr = run_command(ssh_cmd, timeout=120)
    
    if code != 0:
        print(f"{RED}  ❌ Test failed: {stderr}{NC}")
        if stderr:
            print(f"    Error details: {stderr[:200]}")
        return {}
    
    # Debug: show raw output
    if not stdout.strip():
        print(f"{YELLOW}  ⚠ No output received from test script{NC}")
        return {}
    
    # Uncomment for debugging:
    # print(f"  Raw output: {stdout[:500]}")
    
    # Parse results
    consumer_counts = defaultdict(int)
    lines = stdout.strip().split('\n')
    
    # Look for connection results
    for line in lines:
        if "Connection" in line and ":" in line:
            parts = line.split(":", 1)
            if len(parts) > 1:
                namespace = parts[1].strip()
                if namespace and namespace != "Failed":
                    consumer_counts[namespace] += 1
    
    # Also look for the summary line
    for line in lines:
        if "Results:" in line:
            # Parse the X/Y successful format
            import re
            match = re.search(r'(\d+)/(\d+) successful', line)
            if match:
                successful = int(match.group(1))
                if successful > 0 and not consumer_counts:
                    # If we had successful connections but couldn't parse them,
                    # at least note that
                    consumer_counts["unidentified"] = successful
    
    # Display summary
    if consumer_counts:
        print(f"{GREEN}  ✓ Test completed{NC}")
        for consumer, count in consumer_counts.items():
            print(f"    → {consumer}: {count} connections")
    
    return dict(consumer_counts)

def main():
    print(f"{YELLOW}{'='*60}")
    print("NLB LOAD BALANCING TEST (Remote Execution)")
    print(f"{'='*60}{NC}\n")
    
    # Check for PEM file
    if not os.path.exists("test-instance.pem"):
        print(f"{RED}❌ Test instances not deployed yet{NC}")
        print("Run: terraform apply")
        sys.exit(1)
    
    # Get instance IPs
    instance_ips = get_terraform_output("instance_public_ips")
    if not instance_ips or len(instance_ips) == 0:
        print(f"{RED}❌ No instances found{NC}")
        print("Run: terraform apply")
        sys.exit(1)
    
    print(f"{GREEN}Found {len(instance_ips)} test instances{NC}")
    for i, ip in enumerate(instance_ips, 1):
        print(f"  • Instance {i}: {ip}")
    
    # Get NLB endpoint from parent directory
    nlb_endpoint = get_terraform_output("nlb_endpoint")
    if not nlb_endpoint:
        # Try parent directory
        parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        os.chdir(parent_dir)
        nlb_endpoint = get_terraform_output("nlb_endpoint")
        # Also get password while we're here
        password = get_terraform_output("master_password")
        os.chdir(os.path.join(parent_dir, "test-instance"))
    else:
        password = os.environ.get('REDSHIFT_PASSWORD', 'Password123')
    
    if not nlb_endpoint:
        print(f"{RED}❌ Could not get NLB endpoint{NC}")
        sys.exit(1)
    
    print(f"\n{BLUE}NLB Endpoint: {nlb_endpoint}{NC}")
    
    # Test from each instance
    all_results = {}
    for i, instance_ip in enumerate(instance_ips, 1):
        results = test_from_instance(
            instance_ip, 
            i, 
            nlb_endpoint, 
            password
        )
        all_results[f"Instance {i}"] = results
    
    # Summary
    print(f"\n{YELLOW}{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}{NC}\n")
    
    # Analyze stickiness
    sticky_instances = 0
    instance_to_consumer = {}
    
    for instance, results in all_results.items():
        if len(results) == 1:  # All connections went to same consumer
            sticky_instances += 1
            consumer = list(results.keys())[0]
            instance_to_consumer[instance] = consumer
            print(f"{GREEN}✓ {instance} → {consumer} (100% sticky){NC}")
        elif len(results) > 1:
            print(f"{YELLOW}⚠ {instance} connected to multiple consumers:{NC}")
            for consumer, count in results.items():
                print(f"    {consumer}: {count} connections")
        else:
            print(f"{RED}✗ {instance} had no successful connections{NC}")
    
    # Final verdict
    print(f"\n{YELLOW}RESULT:{NC}")
    if sticky_instances == len(all_results) and sticky_instances > 0:
        print(f"{GREEN}✅ Perfect session stickiness!{NC}")
        print("Each instance consistently connects to the same consumer.")
        
        # Check if load is distributed
        unique_consumers = set(instance_to_consumer.values())
        if len(unique_consumers) > 1:
            print(f"{GREEN}✅ Load balancing confirmed!{NC}")
            print(f"Traffic distributed across {len(unique_consumers)} consumers.")
        else:
            print(f"{YELLOW}⚠ All instances routing to same consumer.{NC}")
            print("Check if other consumers are healthy.")
    elif sticky_instances > 0:
        print(f"{YELLOW}⚠️  Mixed results. {sticky_instances}/{len(all_results)} instances showed session stickiness.{NC}")
    else:
        print(f"{RED}❌ No successful connections. Check:{NC}")
        print("  1. Security groups allow EC2 to NLB connections")
        print("  2. NLB target health")
        print("  3. Redshift credentials")
        print("  4. VPC endpoints and routing")
    
    # Show distribution
    if any(all_results.values()):
        print(f"\n{BLUE}Consumer Distribution:{NC}")
        consumer_total = defaultdict(int)
        for results in all_results.values():
            for consumer, count in results.items():
                consumer_total[consumer] += count
        
        total_connections = sum(consumer_total.values())
        for consumer, count in sorted(consumer_total.items()):
            percentage = (count / total_connections) * 100 if total_connections > 0 else 0
            bar = "█" * int(percentage / 2)
            print(f"  {consumer}: {bar} {count}/{total_connections} ({percentage:.0f}%)")

if __name__ == "__main__":
    main()