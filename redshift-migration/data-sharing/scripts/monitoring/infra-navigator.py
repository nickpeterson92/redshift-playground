#!/usr/bin/env python3
"""
Infrastructure Navigator - Comprehensive TUI for AWS Resource Exploration
Navigate through VPC, Redshift, NLB, and all deployed infrastructure
"""

import curses
import time
import subprocess
import json
import os
import threading
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
import sys
from enum import Enum

class ViewMode(Enum):
    MENU = "menu"
    WORKGROUPS = "workgroups"
    VPC = "vpc"
    NLB = "nlb"
    DATA_SHARING = "data_sharing"
    SECURITY = "security"
    COSTS = "costs"

class InfrastructureNavigator:
    def __init__(self):
        self.current_view = ViewMode.MENU
        self.selected_index = 0
        self.scroll_offset = 0
        self.detail_mode = False
        
        # Config
        self.project_name = os.environ.get('PROJECT_NAME', 'airline')
        self.consumer_count = int(os.environ.get('CONSUMER_COUNT', '3'))
        self.aws_region = os.environ.get('AWS_REGION', 'us-west-2')
        
        # Thread safety
        self.state_lock = threading.Lock()
        self.stop_thread = threading.Event()
        
        # Data cache
        self.cache = {
            'workgroups': {},
            'namespaces': {},
            'vpc': {},
            'subnets': [],
            'security_groups': [],
            'nlb': {},
            'target_groups': [],
            'endpoints': [],
            'data_shares': [],
            'costs': {},
            'last_update': None
        }
        
        # Menu items
        self.menu_items = [
            {"name": "📊 Overview Dashboard", "view": ViewMode.MENU, "desc": "System health and status"},
            {"name": "⚡ Redshift Workgroups", "view": ViewMode.WORKGROUPS, "desc": "Serverless clusters and namespaces"},
            {"name": "🌐 VPC & Networking", "view": ViewMode.VPC, "desc": "Network infrastructure and endpoints"},
            {"name": "⚖️  Load Balancer (NLB)", "view": ViewMode.NLB, "desc": "Load balancing and target health"},
            {"name": "🔄 Data Sharing", "view": ViewMode.DATA_SHARING, "desc": "Cross-cluster data shares"},
            {"name": "🔒 Security Groups", "view": ViewMode.SECURITY, "desc": "Security rules and access control"},
            {"name": "💰 Cost Analysis", "view": ViewMode.COSTS, "desc": "RPU usage and estimated costs"},
        ]
    
    def run_aws_command(self, cmd: List[str]) -> Optional[Any]:
        """Run AWS CLI command and return JSON result"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout:
                return json.loads(result.stdout) if result.stdout.strip() else None
        except:
            pass
        return None
    
    def update_all_data(self):
        """Update all infrastructure data"""
        with self.state_lock:
            self.cache['last_update'] = datetime.now()
            
            # Update workgroups
            self.update_workgroups()
            # Update VPC data
            self.update_vpc_data()
            # Update NLB data
            self.update_nlb_data()
            # Update data shares
            self.update_data_shares()
    
    def update_workgroups(self):
        """Update Redshift workgroups and namespaces"""
        # List workgroups
        wg_list = self.run_aws_command([
            "aws", "redshift-serverless", "list-workgroups",
            "--output", "json"
        ])
        
        if wg_list and 'workgroups' in wg_list:
            for wg in wg_list['workgroups']:
                wg_name = wg['workgroupName']
                # Get detailed info
                wg_detail = self.run_aws_command([
                    "aws", "redshift-serverless", "get-workgroup",
                    "--workgroup-name", wg_name,
                    "--output", "json"
                ])
                if wg_detail and 'workgroup' in wg_detail:
                    self.cache['workgroups'][wg_name] = wg_detail['workgroup']
        
        # List namespaces
        ns_list = self.run_aws_command([
            "aws", "redshift-serverless", "list-namespaces",
            "--output", "json"
        ])
        
        if ns_list and 'namespaces' in ns_list:
            for ns in ns_list['namespaces']:
                ns_name = ns['namespaceName']
                # Get detailed info
                ns_detail = self.run_aws_command([
                    "aws", "redshift-serverless", "get-namespace",
                    "--namespace-name", ns_name,
                    "--output", "json"
                ])
                if ns_detail and 'namespace' in ns_detail:
                    self.cache['namespaces'][ns_name] = ns_detail['namespace']
    
    def update_vpc_data(self):
        """Update VPC and networking data"""
        # Get VPCs
        vpcs = self.run_aws_command([
            "aws", "ec2", "describe-vpcs",
            "--filters", f"Name=tag:Name,Values=*{self.project_name}*",
            "--output", "json"
        ])
        
        if vpcs and 'Vpcs' in vpcs and vpcs['Vpcs']:
            self.cache['vpc'] = vpcs['Vpcs'][0]
            vpc_id = self.cache['vpc']['VpcId']
            
            # Get subnets
            subnets = self.run_aws_command([
                "aws", "ec2", "describe-subnets",
                "--filters", f"Name=vpc-id,Values={vpc_id}",
                "--output", "json"
            ])
            if subnets and 'Subnets' in subnets:
                self.cache['subnets'] = subnets['Subnets']
            
            # Get security groups
            sgs = self.run_aws_command([
                "aws", "ec2", "describe-security-groups",
                "--filters", f"Name=vpc-id,Values={vpc_id}",
                "--output", "json"
            ])
            if sgs and 'SecurityGroups' in sgs:
                self.cache['security_groups'] = sgs['SecurityGroups']
        
        # Get VPC endpoints for Redshift
        endpoints = self.run_aws_command([
            "aws", "redshift-serverless", "list-endpoint-access",
            "--output", "json"
        ])
        if endpoints and 'endpoints' in endpoints:
            self.cache['endpoints'] = endpoints['endpoints']
    
    def update_nlb_data(self):
        """Update NLB and target group data"""
        # Get load balancers
        nlbs = self.run_aws_command([
            "aws", "elbv2", "describe-load-balancers",
            "--names", f"{self.project_name}-redshift-nlb",
            "--output", "json"
        ])
        
        if nlbs and 'LoadBalancers' in nlbs and nlbs['LoadBalancers']:
            self.cache['nlb'] = nlbs['LoadBalancers'][0]
            
            # Get target groups
            tgs = self.run_aws_command([
                "aws", "elbv2", "describe-target-groups",
                "--load-balancer-arn", self.cache['nlb']['LoadBalancerArn'],
                "--output", "json"
            ])
            
            if tgs and 'TargetGroups' in tgs:
                self.cache['target_groups'] = tgs['TargetGroups']
                
                # Get target health for each group
                for tg in self.cache['target_groups']:
                    health = self.run_aws_command([
                        "aws", "elbv2", "describe-target-health",
                        "--target-group-arn", tg['TargetGroupArn'],
                        "--output", "json"
                    ])
                    if health and 'TargetHealthDescriptions' in health:
                        tg['TargetHealth'] = health['TargetHealthDescriptions']
    
    def update_data_shares(self):
        """Update data sharing information"""
        # This would require connecting to Redshift directly
        # For now, we'll show available shares based on namespaces
        shares = []
        for ns_name, ns in self.cache['namespaces'].items():
            if 'producer' in ns_name.lower():
                shares.append({
                    'type': 'producer',
                    'namespace': ns_name,
                    'namespace_id': ns.get('namespaceId', 'N/A'),
                    'status': 'ACTIVE' if ns.get('status') == 'AVAILABLE' else 'PENDING'
                })
            else:
                shares.append({
                    'type': 'consumer',
                    'namespace': ns_name,
                    'namespace_id': ns.get('namespaceId', 'N/A'),
                    'status': 'ACTIVE' if ns.get('status') == 'AVAILABLE' else 'PENDING'
                })
        self.cache['data_shares'] = shares
    
    def draw_header(self, stdscr, title):
        """Draw consistent header"""
        height, width = stdscr.getmaxyx()
        
        # Title bar
        header = f" 🚀 Infrastructure Navigator - {title} "
        x = (width - len(header)) // 2
        stdscr.attron(curses.color_pair(4) | curses.A_BOLD)
        stdscr.addstr(0, max(0, x), header[:width])
        stdscr.attroff(curses.color_pair(4) | curses.A_BOLD)
        
        # Status bar
        if self.cache['last_update']:
            elapsed = (datetime.now() - self.cache['last_update']).seconds
            status = f"Last update: {elapsed}s ago | Region: {self.aws_region} | Project: {self.project_name}"
        else:
            status = f"Loading... | Region: {self.aws_region} | Project: {self.project_name}"
        
        stdscr.addstr(1, 2, status[:width-4])
        stdscr.addstr(2, 0, "=" * width)
    
    def draw_menu(self, stdscr):
        """Draw main menu"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Main Menu")
        
        # Overview stats
        y = 4
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "System Overview")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        # Quick stats
        wg_count = len(self.cache['workgroups'])
        wg_available = sum(1 for w in self.cache['workgroups'].values() if w.get('status') == 'AVAILABLE')
        
        stats = [
            f"⚡ Workgroups: {wg_available}/{wg_count} available",
            f"🌐 VPC: {'✓' if self.cache['vpc'] else '○'} configured",
            f"⚖️  NLB: {'✓ Active' if self.cache['nlb'].get('State', {}).get('Code') == 'active' else '○ Pending'}",
            f"🔄 Data Shares: {len([s for s in self.cache['data_shares'] if s['status'] == 'ACTIVE'])} active"
        ]
        
        for stat in stats:
            stdscr.addstr(y, 4, stat)
            y += 1
        
        y += 2
        stdscr.addstr(y, 0, "─" * width)
        y += 2
        
        # Menu items
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "Navigate to:")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        for idx, item in enumerate(self.menu_items[1:], 1):  # Skip overview
            if idx - 1 == self.selected_index:
                stdscr.attron(curses.A_REVERSE)
            
            stdscr.addstr(y, 4, f"{item['name']:<30} {item['desc']}")
            
            if idx - 1 == self.selected_index:
                stdscr.attroff(curses.A_REVERSE)
            y += 2
        
        # Help
        help_text = "↑↓ Navigate | Enter Select | q Back/Quit | r Refresh"
        stdscr.addstr(height - 1, 2, help_text)
    
    def draw_workgroups_view(self, stdscr):
        """Draw detailed workgroups view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Redshift Serverless Workgroups")
        
        y = 4
        
        # Table header
        header = f"{'Workgroup':<30} {'Status':<12} {'Namespace':<20} {'RPUs':<8} {'Endpoint'}"
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, header[:width-4])
        stdscr.attroff(curses.A_BOLD)
        y += 1
        stdscr.addstr(y, 2, "─" * min(width-4, 100))
        y += 1
        
        # List workgroups
        workgroups = list(self.cache['workgroups'].items())
        visible_start = self.scroll_offset
        visible_end = min(visible_start + (height - 10), len(workgroups))
        
        for idx, (name, wg) in enumerate(workgroups[visible_start:visible_end], visible_start):
            if idx == self.selected_index:
                stdscr.attron(curses.A_REVERSE)
            
            status = wg.get('status', 'UNKNOWN')
            if status == 'AVAILABLE':
                status_str = "✓ AVAILABLE"
                color = curses.color_pair(2)
            elif status in ['CREATING', 'MODIFYING']:
                status_str = "⟳ " + status[:9]
                color = curses.color_pair(3)
            else:
                status_str = "✗ " + status[:9]
                color = curses.color_pair(1)
            
            namespace = wg.get('namespaceName', 'N/A')[:18]
            rpus = str(wg.get('baseCapacity', 'N/A'))
            endpoint = wg.get('endpoint', {}).get('address', 'N/A')[:30]
            
            # Draw row
            row = f"{name[:28]:<30} "
            stdscr.addstr(y, 2, row)
            
            stdscr.attron(color)
            stdscr.addstr(f"{status_str:<12}")
            stdscr.attroff(color)
            
            stdscr.addstr(f" {namespace:<20} {rpus:<8} {endpoint}")
            
            if idx == self.selected_index:
                stdscr.attroff(curses.A_REVERSE)
            y += 1
        
        # Detail panel for selected workgroup
        if self.detail_mode and workgroups:
            selected_name, selected_wg = workgroups[self.selected_index]
            y = height - 12
            stdscr.addstr(y, 0, "─" * width)
            y += 1
            
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, f"Details: {selected_name}")
            stdscr.attroff(curses.A_BOLD)
            y += 1
            
            details = [
                f"Namespace ID: {selected_wg.get('namespaceId', 'N/A')}",
                f"Created: {selected_wg.get('createdAt', 'N/A')[:19]}",
                f"Base Capacity: {selected_wg.get('baseCapacity', 'N/A')} RPUs",
                f"Max Capacity: {selected_wg.get('maxCapacity', 'N/A')} RPUs",
                f"Enhanced VPC: {'✓' if selected_wg.get('enhancedVpcRouting') else '✗'}",
                f"Public Access: {'✓' if selected_wg.get('publiclyAccessible') else '✗'}",
                f"Security Groups: {', '.join(selected_wg.get('securityGroupIds', [])[:2])}",
            ]
            
            for detail in details:
                if y < height - 2:
                    stdscr.addstr(y, 4, detail[:width-6])
                    y += 1
        
        # Help
        help_text = "↑↓ Navigate | d Toggle Details | Enter Connect Info | b Back | r Refresh"
        stdscr.addstr(height - 1, 2, help_text[:width-4])
    
    def draw_vpc_view(self, stdscr):
        """Draw VPC and networking view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "VPC & Networking")
        
        y = 4
        
        if self.cache['vpc']:
            vpc = self.cache['vpc']
            
            # VPC Info
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, f"VPC: {vpc['VpcId']}")
            stdscr.attroff(curses.A_BOLD)
            stdscr.addstr(y + 1, 4, f"CIDR: {vpc['CidrBlock']}")
            stdscr.addstr(y + 2, 4, f"State: {vpc['State']}")
            y += 4
            
            # Subnets
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, f"Subnets ({len(self.cache['subnets'])})")
            stdscr.attroff(curses.A_BOLD)
            y += 1
            
            for subnet in self.cache['subnets'][:5]:  # Show first 5
                az = subnet['AvailabilityZone']
                cidr = subnet['CidrBlock']
                available_ips = subnet['AvailableIpAddressCount']
                
                color = curses.color_pair(2) if available_ips > 100 else curses.color_pair(3)
                stdscr.addstr(y, 4, f"{az}: {cidr} - ")
                stdscr.attron(color)
                stdscr.addstr(f"{available_ips} IPs available")
                stdscr.attroff(color)
                y += 1
            
            y += 2
            
            # VPC Endpoints
            if self.cache['endpoints']:
                stdscr.attron(curses.A_BOLD)
                stdscr.addstr(y, 2, f"VPC Endpoints ({len(self.cache['endpoints'])})")
                stdscr.attroff(curses.A_BOLD)
                y += 1
                
                for ep in self.cache['endpoints'][:3]:
                    name = ep.get('endpointName', 'N/A')
                    status = ep.get('endpointStatus', 'N/A')
                    address = ep.get('address', 'N/A')
                    
                    if status == 'ACTIVE':
                        stdscr.attron(curses.color_pair(2))
                        stdscr.addstr(y, 4, f"✓ {name}: {address[:40]}")
                        stdscr.attroff(curses.color_pair(2))
                    else:
                        stdscr.attron(curses.color_pair(3))
                        stdscr.addstr(y, 4, f"⟳ {name}: {status}")
                        stdscr.attroff(curses.color_pair(3))
                    y += 1
        else:
            stdscr.addstr(y, 2, "No VPC data available. Press 'r' to refresh.")
        
        # Help
        help_text = "b Back | r Refresh | q Quit"
        stdscr.addstr(height - 1, 2, help_text)
    
    def draw_nlb_view(self, stdscr):
        """Draw NLB and target health view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Network Load Balancer")
        
        y = 4
        
        if self.cache['nlb']:
            nlb = self.cache['nlb']
            
            # NLB Info
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, f"NLB: {nlb.get('LoadBalancerName', 'N/A')}")
            stdscr.attroff(curses.A_BOLD)
            
            state = nlb.get('State', {}).get('Code', 'unknown')
            if state == 'active':
                stdscr.attron(curses.color_pair(2))
                stdscr.addstr(y + 1, 4, f"✓ State: ACTIVE")
                stdscr.attroff(curses.color_pair(2))
            else:
                stdscr.attron(curses.color_pair(3))
                stdscr.addstr(y + 1, 4, f"⟳ State: {state.upper()}")
                stdscr.attroff(curses.color_pair(3))
            
            stdscr.addstr(y + 2, 4, f"DNS: {nlb.get('DNSName', 'N/A')[:60]}")
            stdscr.addstr(y + 3, 4, f"Scheme: {nlb.get('Scheme', 'N/A')}")
            y += 5
            
            # Target Groups
            if self.cache['target_groups']:
                for tg in self.cache['target_groups']:
                    stdscr.attron(curses.A_BOLD)
                    stdscr.addstr(y, 2, f"Target Group: {tg['TargetGroupName']}")
                    stdscr.attroff(curses.A_BOLD)
                    y += 1
                    
                    stdscr.addstr(y, 4, f"Port: {tg['Port']} | Protocol: {tg['Protocol']}")
                    y += 1
                    
                    # Target health
                    if 'TargetHealth' in tg:
                        healthy = sum(1 for t in tg['TargetHealth'] 
                                    if t.get('TargetHealth', {}).get('State') == 'healthy')
                        total = len(tg['TargetHealth'])
                        
                        stdscr.addstr(y, 4, "Targets: ")
                        if healthy == total:
                            stdscr.attron(curses.color_pair(2))
                            stdscr.addstr(f"✓ {healthy}/{total} healthy")
                            stdscr.attroff(curses.color_pair(2))
                        else:
                            stdscr.attron(curses.color_pair(3))
                            stdscr.addstr(f"⚠ {healthy}/{total} healthy")
                            stdscr.attroff(curses.color_pair(3))
                        y += 2
                        
                        # Show individual targets
                        for target in tg['TargetHealth'][:5]:  # Show first 5
                            target_id = target['Target']['Id']
                            target_state = target['TargetHealth']['State']
                            
                            if target_state == 'healthy':
                                stdscr.attron(curses.color_pair(2))
                                stdscr.addstr(y, 6, f"✓ {target_id}")
                                stdscr.attroff(curses.color_pair(2))
                            else:
                                stdscr.attron(curses.color_pair(1))
                                stdscr.addstr(y, 6, f"✗ {target_id}: {target_state}")
                                stdscr.attroff(curses.color_pair(1))
                            y += 1
        else:
            stdscr.addstr(y, 2, "No NLB data available. Press 'r' to refresh.")
        
        # Help
        help_text = "b Back | r Refresh | q Quit"
        stdscr.addstr(height - 1, 2, help_text)
    
    def draw_data_sharing_view(self, stdscr):
        """Draw data sharing status"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Data Sharing Configuration")
        
        y = 4
        
        # Producer info
        producers = [s for s in self.cache['data_shares'] if s['type'] == 'producer']
        consumers = [s for s in self.cache['data_shares'] if s['type'] == 'consumer']
        
        if producers:
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, "Producer Namespace")
            stdscr.attroff(curses.A_BOLD)
            y += 1
            
            for prod in producers:
                stdscr.addstr(y, 4, f"Namespace: {prod['namespace']}")
                stdscr.addstr(y + 1, 4, f"ID: {prod['namespace_id']}")
                if prod['status'] == 'ACTIVE':
                    stdscr.attron(curses.color_pair(2))
                    stdscr.addstr(y + 2, 4, "✓ Ready for data sharing")
                    stdscr.attroff(curses.color_pair(2))
                y += 4
        
        # Consumer info
        if consumers:
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, f"Consumer Namespaces ({len(consumers)})")
            stdscr.attroff(curses.A_BOLD)
            y += 1
            
            for idx, cons in enumerate(consumers, 1):
                status_icon = "✓" if cons['status'] == 'ACTIVE' else "⟳"
                color = curses.color_pair(2) if cons['status'] == 'ACTIVE' else curses.color_pair(3)
                
                stdscr.attron(color)
                stdscr.addstr(y, 4, f"{status_icon} Consumer {idx}: {cons['namespace']}")
                stdscr.attroff(color)
                stdscr.addstr(y + 1, 6, f"ID: {cons['namespace_id']}")
                y += 2
        
        y += 2
        
        # SQL commands helper
        if producers and consumers and all(c['status'] == 'ACTIVE' for c in consumers):
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, "Ready for Data Sharing! Run these SQL commands:")
            stdscr.attroff(curses.A_BOLD)
            y += 2
            
            stdscr.addstr(y, 4, "On Producer:")
            y += 1
            stdscr.addstr(y, 6, "CREATE DATASHARE airline_share SET PUBLICACCESSIBLE TRUE;")
            y += 1
            
            for cons in consumers:
                stdscr.addstr(y, 6, f"GRANT USAGE ON DATASHARE airline_share TO NAMESPACE '{cons['namespace_id']}';")
                y += 1
        
        # Help
        help_text = "b Back | r Refresh | q Quit"
        stdscr.addstr(height - 1, 2, help_text)
    
    def background_updater(self):
        """Background thread to update data"""
        while not self.stop_thread.is_set():
            self.update_all_data()
            self.stop_thread.wait(10)  # Update every 10 seconds
    
    def run(self, stdscr):
        """Main curses loop"""
        # Setup colors
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_RED, -1)
        curses.init_pair(2, curses.COLOR_GREEN, -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)
        curses.init_pair(4, curses.COLOR_CYAN, -1)
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)
        curses.init_pair(6, curses.COLOR_BLUE, -1)
        
        # Configure screen
        curses.curs_set(0)
        stdscr.nodelay(1)
        stdscr.timeout(100)
        
        # Initial data load
        self.update_all_data()
        
        # Start background updater
        updater_thread = threading.Thread(target=self.background_updater, daemon=True)
        updater_thread.start()
        
        try:
            while True:
                height, width = stdscr.getmaxyx()
                stdscr.erase()
                
                # Draw current view
                if self.current_view == ViewMode.MENU:
                    self.draw_menu(stdscr)
                elif self.current_view == ViewMode.WORKGROUPS:
                    self.draw_workgroups_view(stdscr)
                elif self.current_view == ViewMode.VPC:
                    self.draw_vpc_view(stdscr)
                elif self.current_view == ViewMode.NLB:
                    self.draw_nlb_view(stdscr)
                elif self.current_view == ViewMode.DATA_SHARING:
                    self.draw_data_sharing_view(stdscr)
                
                stdscr.refresh()
                
                # Handle input
                key = stdscr.getch()
                
                if key == ord('q'):
                    if self.current_view == ViewMode.MENU:
                        break
                    else:
                        self.current_view = ViewMode.MENU
                        self.selected_index = 0
                        self.scroll_offset = 0
                        self.detail_mode = False
                
                elif key == ord('b'):  # Back
                    if self.current_view != ViewMode.MENU:
                        self.current_view = ViewMode.MENU
                        self.selected_index = 0
                        self.scroll_offset = 0
                        self.detail_mode = False
                
                elif key == ord('r'):  # Refresh
                    self.update_all_data()
                
                elif key == ord('d'):  # Toggle details
                    if self.current_view == ViewMode.WORKGROUPS:
                        self.detail_mode = not self.detail_mode
                
                elif key == curses.KEY_UP:
                    if self.selected_index > 0:
                        self.selected_index -= 1
                        if self.selected_index < self.scroll_offset:
                            self.scroll_offset = self.selected_index
                
                elif key == curses.KEY_DOWN:
                    max_index = len(self.menu_items) - 2 if self.current_view == ViewMode.MENU else 10
                    if self.selected_index < max_index:
                        self.selected_index += 1
                        visible_height = height - 15
                        if self.selected_index >= self.scroll_offset + visible_height:
                            self.scroll_offset = self.selected_index - visible_height + 1
                
                elif key in [curses.KEY_ENTER, ord('\n'), 10]:
                    if self.current_view == ViewMode.MENU:
                        selected_item = self.menu_items[self.selected_index + 1]
                        self.current_view = selected_item['view']
                        self.selected_index = 0
                        self.scroll_offset = 0
                
        finally:
            self.stop_thread.set()

def main():
    navigator = InfrastructureNavigator()
    try:
        curses.wrapper(navigator.run)
    except KeyboardInterrupt:
        print("\nExiting Infrastructure Navigator")

if __name__ == "__main__":
    main()