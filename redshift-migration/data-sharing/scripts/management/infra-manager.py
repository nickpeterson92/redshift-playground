#!/usr/bin/env python3
"""
Infrastructure Manager - Full Configuration Management for AWS Resources
Navigate, monitor, and modify all deployed infrastructure
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
    WORKGROUP_EDIT = "workgroup_edit"
    VPC = "vpc"
    NLB = "nlb"
    SECURITY = "security"
    SECURITY_EDIT = "security_edit"
    SCALING = "scaling"
    MAINTENANCE = "maintenance"

class EditMode(Enum):
    NONE = "none"
    CAPACITY = "capacity"
    SECURITY = "security"
    NETWORK = "network"
    TAGS = "tags"

class InfrastructureManager:
    def __init__(self):
        self.current_view = ViewMode.MENU
        self.edit_mode = EditMode.NONE
        self.selected_index = 0
        self.scroll_offset = 0
        self.detail_mode = False
        self.edit_buffer = ""
        self.confirm_action = None
        self.status_message = ""
        self.status_type = "info"  # info, success, error, warning
        
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
            'last_update': None
        }
        
        # Currently selected resources
        self.selected_workgroup = None
        self.selected_security_group = None
        self.selected_target_group = None
        
        # Menu items
        self.menu_items = [
            {"name": "Overview Dashboard", "view": ViewMode.MENU, "desc": "System health and status"},
            {"name": "Manage Workgroups", "view": ViewMode.WORKGROUPS, "desc": "Configure Redshift Serverless"},
            {"name": "Network Configuration", "view": ViewMode.VPC, "desc": "VPC and endpoint settings"},
            {"name": "Load Balancer", "view": ViewMode.NLB, "desc": "NLB and target management"},
            {"name": "Security Groups", "view": ViewMode.SECURITY, "desc": "Firewall rules and access"},
            {"name": "Auto-Scaling", "view": ViewMode.SCALING, "desc": "Capacity and scaling policies"},
            {"name": "Maintenance", "view": ViewMode.MAINTENANCE, "desc": "Updates and maintenance windows"},
        ]
    
    def run_aws_command(self, cmd: List[str], show_output=False) -> Optional[Any]:
        """Run AWS CLI command and return JSON result"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                if result.stdout and result.stdout.strip():
                    try:
                        return json.loads(result.stdout)
                    except:
                        return result.stdout
                return True
            else:
                if show_output and result.stderr:
                    self.set_status(f"Error: {result.stderr[:100]}", "error")
                return None
        except subprocess.TimeoutExpired:
            self.set_status("Command timed out", "error")
            return None
        except Exception as e:
            self.set_status(f"Error: {str(e)[:100]}", "error")
            return None
    
    def set_status(self, message: str, status_type: str = "info"):
        """Set status message"""
        with self.state_lock:
            self.status_message = message
            self.status_type = status_type
    
    def update_workgroup_capacity(self, workgroup_name: str, base_capacity: int, max_capacity: Optional[int] = None):
        """Update workgroup capacity settings"""
        cmd = [
            "aws", "redshift-serverless", "update-workgroup",
            "--workgroup-name", workgroup_name,
            "--base-capacity", str(base_capacity)
        ]
        
        if max_capacity:
            cmd.extend(["--max-capacity", str(max_capacity)])
        
        cmd.extend(["--output", "json"])
        
        self.set_status(f"Updating {workgroup_name} capacity...", "info")
        result = self.run_aws_command(cmd, show_output=True)
        
        if result:
            self.set_status(f"Successfully updated {workgroup_name} capacity", "success")
            self.update_workgroups()  # Refresh data
            return True
        return False
    
    def update_workgroup_security(self, workgroup_name: str, security_group_ids: List[str]):
        """Update workgroup security groups"""
        cmd = [
            "aws", "redshift-serverless", "update-workgroup",
            "--workgroup-name", workgroup_name,
            "--security-group-ids"
        ] + security_group_ids + ["--output", "json"]
        
        self.set_status(f"Updating {workgroup_name} security groups...", "info")
        result = self.run_aws_command(cmd, show_output=True)
        
        if result:
            self.set_status(f"Successfully updated {workgroup_name} security groups", "success")
            self.update_workgroups()
            return True
        return False
    
    def pause_workgroup(self, workgroup_name: str):
        """Pause a workgroup to save costs"""
        # Note: This is a placeholder - actual implementation depends on AWS API
        self.set_status(f"Pausing {workgroup_name}...", "info")
        # In reality, you might scale to 0 or use a different approach
        return self.update_workgroup_capacity(workgroup_name, 0)
    
    def resume_workgroup(self, workgroup_name: str, capacity: int = 32):
        """Resume a paused workgroup"""
        self.set_status(f"Resuming {workgroup_name}...", "info")
        return self.update_workgroup_capacity(workgroup_name, capacity)
    
    def add_security_group_rule(self, sg_id: str, protocol: str, port: int, source: str, description: str = ""):
        """Add ingress rule to security group"""
        cmd = [
            "aws", "ec2", "authorize-security-group-ingress",
            "--group-id", sg_id,
            "--protocol", protocol,
            "--port", str(port),
            "--source-group", source if source.startswith("sg-") else None,
            "--cidr", source if "/" in source else None
        ]
        
        if description:
            cmd.extend(["--group-rule-description", description])
        
        cmd = [c for c in cmd if c is not None]  # Remove None values
        cmd.extend(["--output", "json"])
        
        self.set_status(f"Adding security rule to {sg_id}...", "info")
        result = self.run_aws_command(cmd, show_output=True)
        
        if result:
            self.set_status("Successfully added security rule", "success")
            self.update_vpc_data()
            return True
        return False
    
    def update_target_group_health_check(self, tg_arn: str, interval: int, timeout: int, threshold: int):
        """Update target group health check settings"""
        cmd = [
            "aws", "elbv2", "modify-target-group",
            "--target-group-arn", tg_arn,
            "--health-check-interval-seconds", str(interval),
            "--health-check-timeout-seconds", str(timeout),
            "--healthy-threshold-count", str(threshold),
            "--output", "json"
        ]
        
        self.set_status("Updating health check settings...", "info")
        result = self.run_aws_command(cmd, show_output=True)
        
        if result:
            self.set_status("Successfully updated health check", "success")
            self.update_nlb_data()
            return True
        return False
    
    def update_all_data(self):
        """Update all infrastructure data"""
        with self.state_lock:
            self.cache['last_update'] = datetime.now()
            
            # Update all resource types
            self.update_workgroups()
            self.update_vpc_data()
            self.update_nlb_data()
    
    def update_workgroups(self):
        """Update Redshift workgroups and namespaces"""
        wg_list = self.run_aws_command([
            "aws", "redshift-serverless", "list-workgroups",
            "--output", "json"
        ])
        
        if wg_list and 'workgroups' in wg_list:
            for wg in wg_list['workgroups']:
                wg_name = wg['workgroupName']
                wg_detail = self.run_aws_command([
                    "aws", "redshift-serverless", "get-workgroup",
                    "--workgroup-name", wg_name,
                    "--output", "json"
                ])
                if wg_detail and 'workgroup' in wg_detail:
                    self.cache['workgroups'][wg_name] = wg_detail['workgroup']
        
        # Update namespaces
        ns_list = self.run_aws_command([
            "aws", "redshift-serverless", "list-namespaces",
            "--output", "json"
        ])
        
        if ns_list and 'namespaces' in ns_list:
            for ns in ns_list['namespaces']:
                ns_name = ns['namespaceName']
                self.cache['namespaces'][ns_name] = ns
    
    def update_vpc_data(self):
        """Update VPC and networking data"""
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
    
    def update_nlb_data(self):
        """Update NLB and target group data"""
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
                
                # Get target health
                for tg in self.cache['target_groups']:
                    health = self.run_aws_command([
                        "aws", "elbv2", "describe-target-health",
                        "--target-group-arn", tg['TargetGroupArn'],
                        "--output", "json"
                    ])
                    if health and 'TargetHealthDescriptions' in health:
                        tg['TargetHealth'] = health['TargetHealthDescriptions']
    
    def draw_header(self, stdscr, title):
        """Draw consistent header"""
        height, width = stdscr.getmaxyx()
        
        # Title bar
        header = f" Infrastructure Manager - {title} "
        x = (width - len(header)) // 2
        stdscr.attron(curses.color_pair(4) | curses.A_BOLD)
        stdscr.addstr(0, max(0, x), header[:width])
        stdscr.attroff(curses.color_pair(4) | curses.A_BOLD)
        
        # Status bar
        if self.cache['last_update']:
            elapsed = (datetime.now() - self.cache['last_update']).seconds
            status = f"Updated: {elapsed}s ago | Region: {self.aws_region} | Project: {self.project_name}"
        else:
            status = f"Loading... | Region: {self.aws_region} | Project: {self.project_name}"
        
        stdscr.addstr(1, 2, status[:width-4])
        
        # Status message if any
        if self.status_message:
            color = {
                "info": curses.color_pair(4),
                "success": curses.color_pair(2),
                "error": curses.color_pair(1),
                "warning": curses.color_pair(3)
            }.get(self.status_type, curses.color_pair(5))
            
            stdscr.attron(color)
            stdscr.addstr(1, width - len(self.status_message) - 2, self.status_message[:50])
            stdscr.attroff(color)
        
        stdscr.addstr(2, 0, "=" * width)
    
    def draw_menu(self, stdscr):
        """Draw main menu"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Main Menu")
        
        y = 4
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "System Overview")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        # Quick stats
        wg_count = len(self.cache['workgroups'])
        wg_available = sum(1 for w in self.cache['workgroups'].values() if w.get('status') == 'AVAILABLE')
        
        stats = [
            f"Workgroups: {wg_available}/{wg_count} available",
            f"VPC: {'Configured' if self.cache['vpc'] else 'Not found'}",
            f"NLB: {self.cache['nlb'].get('State', {}).get('Code', 'unknown').upper() if self.cache['nlb'] else 'Not found'}",
            f"Security Groups: {len(self.cache['security_groups'])}"
        ]
        
        for stat in stats:
            stdscr.addstr(y, 4, stat)
            y += 1
        
        y += 2
        stdscr.addstr(y, 0, "-" * width)
        y += 2
        
        # Menu items
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "Management Options:")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        for idx, item in enumerate(self.menu_items[1:], 1):
            if idx - 1 == self.selected_index:
                stdscr.attron(curses.A_REVERSE)
            
            stdscr.addstr(y, 4, f"{idx}. {item['name']:<25} - {item['desc']}")
            
            if idx - 1 == self.selected_index:
                stdscr.attroff(curses.A_REVERSE)
            y += 1
        
        # Help
        y = height - 3
        stdscr.addstr(y, 0, "-" * width)
        help_text = "↑↓ Navigate | Enter Select | q Quit | r Refresh"
        stdscr.addstr(height - 1, 2, help_text)
    
    def draw_workgroups_view(self, stdscr):
        """Draw workgroups management view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Workgroup Management")
        
        y = 4
        
        # If in edit mode, show edit interface
        if self.current_view == ViewMode.WORKGROUP_EDIT and self.selected_workgroup:
            self.draw_workgroup_edit(stdscr, y)
            return
        
        # Table header
        header = f"{'Workgroup':<25} {'Status':<12} {'Base RPU':<10} {'Max RPU':<10} {'Actions'}"
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, header[:width-4])
        stdscr.attroff(curses.A_BOLD)
        y += 1
        stdscr.addstr(y, 2, "-" * min(width-4, 80))
        y += 1
        
        # List workgroups
        workgroups = list(self.cache['workgroups'].items())
        visible_start = self.scroll_offset
        visible_end = min(visible_start + (height - 12), len(workgroups))
        
        for idx, (name, wg) in enumerate(workgroups[visible_start:visible_end], visible_start):
            if idx == self.selected_index:
                stdscr.attron(curses.A_REVERSE)
            
            status = wg.get('status', 'UNKNOWN')
            if status == 'AVAILABLE':
                status_str = "AVAILABLE"
                color = curses.color_pair(2)
            elif status in ['CREATING', 'MODIFYING']:
                status_str = status
                color = curses.color_pair(3)
            else:
                status_str = status
                color = curses.color_pair(1)
            
            base_capacity = wg.get('baseCapacity', 0)
            max_capacity = wg.get('maxCapacity', 0)
            
            # Draw row
            row = f"{name[:23]:<25} "
            stdscr.addstr(y, 2, row)
            
            stdscr.attron(color)
            stdscr.addstr(f"{status_str:<12}")
            stdscr.attroff(color)
            
            stdscr.addstr(f" {base_capacity:<10} {max_capacity:<10}")
            
            if idx == self.selected_index:
                stdscr.attroff(curses.A_REVERSE)
            y += 1
        
        # Action menu at bottom
        y = height - 6
        stdscr.addstr(y, 0, "-" * width)
        y += 1
        
        if workgroups and self.selected_index < len(workgroups):
            selected_name, selected_wg = workgroups[self.selected_index]
            stdscr.attron(curses.A_BOLD)
            stdscr.addstr(y, 2, f"Selected: {selected_name}")
            stdscr.attroff(curses.A_BOLD)
            y += 1
            
            actions = "e Edit Capacity | s Security Groups | p Pause/Resume | t Tags | d Delete"
            stdscr.addstr(y, 2, actions[:width-4])
        
        # Help
        help_text = "↑↓ Navigate | Action Keys Above | b Back | r Refresh"
        stdscr.addstr(height - 1, 2, help_text[:width-4])
    
    def draw_workgroup_edit(self, stdscr, start_y):
        """Draw workgroup edit interface"""
        height, width = stdscr.getmaxyx()
        y = start_y
        
        wg = self.cache['workgroups'].get(self.selected_workgroup, {})
        
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, f"Editing: {self.selected_workgroup}")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        # Current settings
        stdscr.addstr(y, 2, "Current Settings:")
        y += 1
        stdscr.addstr(y, 4, f"Base Capacity: {wg.get('baseCapacity', 'N/A')} RPUs")
        y += 1
        stdscr.addstr(y, 4, f"Max Capacity: {wg.get('maxCapacity', 'N/A')} RPUs")
        y += 1
        stdscr.addstr(y, 4, f"Status: {wg.get('status', 'N/A')}")
        y += 2
        
        # Edit form
        stdscr.addstr(y, 2, "-" * 50)
        y += 1
        
        if self.edit_mode == EditMode.CAPACITY:
            stdscr.addstr(y, 2, "New Capacity Settings:")
            y += 1
            stdscr.addstr(y, 4, "Base RPUs (8-512): ")
            stdscr.attron(curses.A_REVERSE)
            stdscr.addstr(self.edit_buffer + "_")
            stdscr.attroff(curses.A_REVERSE)
            y += 2
            stdscr.addstr(y, 4, "Enter to confirm, ESC to cancel")
        
        elif self.confirm_action:
            stdscr.attron(curses.color_pair(3))
            stdscr.addstr(y, 2, f"Confirm: {self.confirm_action}?")
            stdscr.attroff(curses.color_pair(3))
            y += 1
            stdscr.addstr(y, 4, "y = Yes, n = No")
    
    def draw_security_view(self, stdscr):
        """Draw security groups management view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Security Group Management")
        
        y = 4
        
        # List security groups
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "Security Groups:")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        for idx, sg in enumerate(self.cache['security_groups']):
            if idx == self.selected_index:
                stdscr.attron(curses.A_REVERSE)
            
            sg_id = sg['GroupId']
            sg_name = sg.get('GroupName', 'N/A')
            rule_count = len(sg.get('IpPermissions', []))
            
            stdscr.addstr(y, 4, f"{sg_id} - {sg_name} ({rule_count} rules)")
            
            if idx == self.selected_index:
                stdscr.attroff(curses.A_REVERSE)
                
                # Show rules for selected group
                y += 1
                for rule in sg.get('IpPermissions', [])[:3]:
                    protocol = rule.get('IpProtocol', 'all')
                    from_port = rule.get('FromPort', 'N/A')
                    to_port = rule.get('ToPort', 'N/A')
                    
                    if rule.get('IpRanges'):
                        source = rule['IpRanges'][0].get('CidrIp', 'N/A')
                    elif rule.get('UserIdGroupPairs'):
                        source = rule['UserIdGroupPairs'][0].get('GroupId', 'N/A')
                    else:
                        source = 'N/A'
                    
                    stdscr.addstr(y, 8, f"  {protocol} {from_port}-{to_port} from {source}"[:width-10])
                    y += 1
            else:
                y += 1
        
        # Actions
        y = height - 4
        stdscr.addstr(y, 0, "-" * width)
        y += 1
        actions = "a Add Rule | d Delete Rule | e Edit | c Copy"
        stdscr.addstr(y, 2, actions)
        
        # Help
        help_text = "↑↓ Navigate | Action Keys Above | b Back | r Refresh"
        stdscr.addstr(height - 1, 2, help_text)
    
    def draw_scaling_view(self, stdscr):
        """Draw auto-scaling configuration view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Auto-Scaling Configuration")
        
        y = 4
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "Scaling Policies")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        # Show workgroup scaling settings
        for name, wg in self.cache['workgroups'].items():
            base = wg.get('baseCapacity', 0)
            max_cap = wg.get('maxCapacity', 0)
            
            stdscr.addstr(y, 4, f"{name}:")
            y += 1
            
            # Visual representation of scaling range
            scale_width = 40
            if max_cap > 0:
                base_pos = int((base / max_cap) * scale_width)
                
                stdscr.addstr(y, 6, "[")
                for i in range(scale_width):
                    if i < base_pos:
                        stdscr.attron(curses.color_pair(2))
                        stdscr.addstr("=")
                        stdscr.attroff(curses.color_pair(2))
                    else:
                        stdscr.addstr("-")
                stdscr.addstr("]")
                stdscr.addstr(f" {base}-{max_cap} RPUs")
            else:
                stdscr.addstr(y, 6, f"Fixed: {base} RPUs")
            y += 2
        
        y += 1
        stdscr.addstr(y, 2, "-" * 60)
        y += 1
        
        # Scaling recommendations
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "Recommendations:")
        stdscr.attroff(curses.A_BOLD)
        y += 1
        
        recommendations = [
            "- Set max capacity 2-3x base for burst workloads",
            "- Use 32 RPU base for development environments",
            "- Use 128+ RPU base for production workloads",
            "- Enable auto-pause for dev/test to save costs"
        ]
        
        for rec in recommendations:
            if y < height - 3:
                stdscr.addstr(y, 4, rec[:width-6])
                y += 1
        
        # Help
        help_text = "e Edit Scaling | p Set Policy | b Back | r Refresh"
        stdscr.addstr(height - 1, 2, help_text)
    
    def draw_maintenance_view(self, stdscr):
        """Draw maintenance and operations view"""
        height, width = stdscr.getmaxyx()
        self.draw_header(stdscr, "Maintenance & Operations")
        
        y = 4
        
        # Quick actions
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "Quick Actions:")
        stdscr.attroff(curses.A_BOLD)
        y += 2
        
        actions = [
            ("1", "Pause All Non-Production Workgroups", "Save costs during off-hours"),
            ("2", "Resume All Workgroups", "Restore full capacity"),
            ("3", "Backup Configuration", "Export current settings"),
            ("4", "Apply Security Updates", "Update security groups"),
            ("5", "Optimize Target Health Checks", "Tune NLB settings"),
            ("6", "Clean Up Unused Resources", "Remove orphaned resources"),
        ]
        
        for key, action, desc in actions:
            if y < height - 8:
                stdscr.addstr(y, 4, f"[{key}] {action}")
                stdscr.addstr(y + 1, 8, f"    {desc}")
                y += 2
        
        y += 1
        stdscr.addstr(y, 2, "-" * 60)
        y += 1
        
        # System health
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(y, 2, "System Health:")
        stdscr.attroff(curses.A_BOLD)
        y += 1
        
        # Calculate health metrics
        total_wg = len(self.cache['workgroups'])
        available_wg = sum(1 for w in self.cache['workgroups'].values() if w.get('status') == 'AVAILABLE')
        
        if total_wg > 0:
            health_pct = (available_wg / total_wg) * 100
            if health_pct == 100:
                color = curses.color_pair(2)
                status = "Healthy"
            elif health_pct >= 75:
                color = curses.color_pair(3)
                status = "Degraded"
            else:
                color = curses.color_pair(1)
                status = "Critical"
            
            stdscr.attron(color)
            stdscr.addstr(y, 4, f"Overall Status: {status} ({health_pct:.0f}%)")
            stdscr.attroff(color)
        
        # Help
        help_text = "Number Keys for Actions | b Back | r Refresh"
        stdscr.addstr(height - 1, 2, help_text)
    
    def handle_workgroup_action(self, key):
        """Handle actions in workgroup view"""
        if not self.cache['workgroups']:
            return
        
        workgroups = list(self.cache['workgroups'].items())
        if self.selected_index >= len(workgroups):
            return
        
        selected_name, selected_wg = workgroups[self.selected_index]
        
        if key == ord('e'):  # Edit capacity
            self.selected_workgroup = selected_name
            self.current_view = ViewMode.WORKGROUP_EDIT
            self.edit_mode = EditMode.CAPACITY
            self.edit_buffer = str(selected_wg.get('baseCapacity', 32))
        
        elif key == ord('p'):  # Pause/Resume
            if selected_wg.get('baseCapacity', 0) > 0:
                self.confirm_action = f"Pause {selected_name}"
            else:
                self.confirm_action = f"Resume {selected_name}"
        
        elif key == ord('s'):  # Security groups
            self.selected_workgroup = selected_name
            self.current_view = ViewMode.SECURITY
    
    def handle_edit_input(self, key):
        """Handle input in edit mode"""
        if key == 27:  # ESC
            self.edit_mode = EditMode.NONE
            self.edit_buffer = ""
            self.current_view = ViewMode.WORKGROUPS
        
        elif key in [curses.KEY_ENTER, ord('\n'), 10]:
            if self.edit_mode == EditMode.CAPACITY:
                try:
                    new_capacity = int(self.edit_buffer)
                    if 8 <= new_capacity <= 512:
                        self.update_workgroup_capacity(self.selected_workgroup, new_capacity)
                        self.edit_mode = EditMode.NONE
                        self.edit_buffer = ""
                        self.current_view = ViewMode.WORKGROUPS
                    else:
                        self.set_status("Capacity must be between 8 and 512", "error")
                except ValueError:
                    self.set_status("Invalid number", "error")
        
        elif key == curses.KEY_BACKSPACE or key == 127:
            if self.edit_buffer:
                self.edit_buffer = self.edit_buffer[:-1]
        
        elif chr(key).isdigit() and len(self.edit_buffer) < 3:
            self.edit_buffer += chr(key)
    
    def handle_confirmation(self, key):
        """Handle confirmation dialogs"""
        if key == ord('y'):
            if "Pause" in self.confirm_action:
                wg_name = self.confirm_action.split()[-1]
                self.pause_workgroup(wg_name)
            elif "Resume" in self.confirm_action:
                wg_name = self.confirm_action.split()[-1]
                self.resume_workgroup(wg_name)
            
            self.confirm_action = None
        
        elif key == ord('n'):
            self.confirm_action = None
    
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
                elif self.current_view in [ViewMode.WORKGROUPS, ViewMode.WORKGROUP_EDIT]:
                    self.draw_workgroups_view(stdscr)
                elif self.current_view == ViewMode.SECURITY:
                    self.draw_security_view(stdscr)
                elif self.current_view == ViewMode.SCALING:
                    self.draw_scaling_view(stdscr)
                elif self.current_view == ViewMode.MAINTENANCE:
                    self.draw_maintenance_view(stdscr)
                
                stdscr.refresh()
                
                # Handle input
                key = stdscr.getch()
                
                # Handle confirmations first
                if self.confirm_action:
                    self.handle_confirmation(key)
                    continue
                
                # Handle edit mode
                if self.edit_mode != EditMode.NONE:
                    self.handle_edit_input(key)
                    continue
                
                # Normal navigation
                if key == ord('q'):
                    if self.current_view == ViewMode.MENU:
                        break
                    else:
                        self.current_view = ViewMode.MENU
                        self.selected_index = 0
                        self.scroll_offset = 0
                
                elif key == ord('b'):  # Back
                    if self.current_view != ViewMode.MENU:
                        self.current_view = ViewMode.MENU
                        self.selected_index = 0
                        self.scroll_offset = 0
                        self.edit_mode = EditMode.NONE
                        self.edit_buffer = ""
                
                elif key == ord('r'):  # Refresh
                    self.update_all_data()
                    self.set_status("Data refreshed", "success")
                
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
                
                # View-specific actions
                elif self.current_view == ViewMode.WORKGROUPS:
                    self.handle_workgroup_action(key)
                
                elif self.current_view == ViewMode.MAINTENANCE:
                    if ord('1') <= key <= ord('6'):
                        action_num = key - ord('0')
                        self.set_status(f"Executing action {action_num}...", "info")
                        # Implement specific actions here
                
                # Clear old status messages
                if self.status_message and (datetime.now() - self.cache.get('last_update', datetime.now())).seconds > 5:
                    self.status_message = ""
        
        finally:
            self.stop_thread.set()

def main():
    manager = InfrastructureManager()
    try:
        curses.wrapper(manager.run)
    except KeyboardInterrupt:
        print("\nExiting Infrastructure Manager")

if __name__ == "__main__":
    main()