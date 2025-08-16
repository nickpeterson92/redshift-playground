#!/usr/bin/env python3
"""
Detailed Redshift Serverless Workgroup Monitor - Curses TUI
Ultra-smooth monitoring with detailed workgroup information
"""

import curses
import time
import subprocess
import json
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import sys

class WorkgroupMonitor:
    def __init__(self):
        self.start_time = datetime.now()
        self.refresh_interval = 2  # AWS update interval
        self.animation_frame = 0
        
        # Thread safety
        self.state_lock = threading.Lock()
        self.stop_thread = threading.Event()
        
        # Workgroup data
        self.workgroups = {}
        self.namespaces = {}
        self.recent_activity = []
        self.issues = []
        
        # UI state
        self.selected_row = 0
        self.scroll_offset = 0
        
    def run_aws_command(self, cmd: List[str]) -> Optional[Dict]:
        """Run AWS CLI command and return JSON"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout:
                return json.loads(result.stdout) if result.stdout.strip() else None
        except:
            pass
        return None
    
    def get_workgroup_details(self, wg_name: str) -> Dict:
        """Get detailed workgroup information"""
        details = self.run_aws_command([
            "aws", "redshift-serverless", "get-workgroup",
            "--workgroup-name", wg_name,
            "--output", "json"
        ])
        
        if not details or 'workgroup' not in details:
            return {
                'status': 'NOT_FOUND',
                'namespace': 'N/A',
                'baseCapacity': 0,
                'endpoint': 'N/A',
                'createdAt': None,
                'enhancedVpcRouting': False,
                'publiclyAccessible': False
            }
        
        wg = details['workgroup']
        endpoint = wg.get('endpoint', {}).get('address', 'N/A')
        
        # Calculate age
        created_at = wg.get('createdAt')
        age_str = "N/A"
        if created_at:
            try:
                # Parse ISO format timestamp
                created_dt = datetime.fromisoformat(created_at.replace('Z', '+00:00').split('.')[0])
                age = datetime.now() - created_dt
                if age.days > 0:
                    age_str = f"{age.days}d"
                elif age.seconds > 3600:
                    age_str = f"{age.seconds // 3600}h"
                else:
                    age_str = f"{age.seconds // 60}m"
            except:
                age_str = "N/A"
        
        return {
            'status': wg.get('status', 'UNKNOWN'),
            'namespace': wg.get('namespaceName', 'N/A'),
            'baseCapacity': wg.get('baseCapacity', 0),
            'maxCapacity': wg.get('maxCapacity', 0),
            'endpoint': endpoint if endpoint else 'N/A',
            'createdAt': created_at,
            'age': age_str,
            'enhancedVpcRouting': wg.get('enhancedVpcRouting', False),
            'publiclyAccessible': wg.get('publiclyAccessible', False),
            'subnetIds': wg.get('subnetIds', []),
            'securityGroupIds': wg.get('securityGroupIds', [])
        }
    
    def get_namespace_details(self, ns_name: str) -> Dict:
        """Get namespace information"""
        details = self.run_aws_command([
            "aws", "redshift-serverless", "get-namespace",
            "--namespace-name", ns_name,
            "--output", "json"
        ])
        
        if not details or 'namespace' not in details:
            return {'status': 'NOT_FOUND', 'dbName': 'N/A', 'adminUsername': 'N/A'}
        
        ns = details['namespace']
        return {
            'status': ns.get('status', 'UNKNOWN'),
            'dbName': ns.get('dbName', 'N/A'),
            'adminUsername': ns.get('adminUsername', 'N/A'),
            'iamRoles': ns.get('iamRoles', [])
        }
    
    def check_issues(self):
        """Check for deployment issues"""
        issues = []
        
        with self.state_lock:
            # Check for stuck workgroups
            for name, details in self.workgroups.items():
                if details['status'] == 'MODIFYING' and details['age'] != 'N/A':
                    try:
                        # Parse age to check if > 10 minutes
                        if 'm' in details['age']:
                            minutes = int(details['age'].replace('m', ''))
                            if minutes > 10:
                                issues.append(f"⚠️  {name} stuck in MODIFYING for {minutes}m")
                        elif 'h' in details['age'] or 'd' in details['age']:
                            issues.append(f"⚠️  {name} stuck in MODIFYING for {details['age']}")
                    except:
                        pass
                
                if details['status'] in ['ERROR', 'FAILED']:
                    issues.append(f"❌ {name} in ERROR state")
            
            self.issues = issues[:5]  # Keep only last 5 issues
    
    def update_workgroups(self):
        """Update workgroup information in background"""
        # List all workgroups
        result = self.run_aws_command([
            "aws", "redshift-serverless", "list-workgroups",
            "--query", "workgroups[*].workgroupName",
            "--output", "json"
        ])
        
        if result:
            workgroups = {}
            for wg_name in result:
                details = self.get_workgroup_details(wg_name)
                workgroups[wg_name] = details
            
            with self.state_lock:
                self.workgroups = workgroups
        
        # List all namespaces
        ns_result = self.run_aws_command([
            "aws", "redshift-serverless", "list-namespaces",
            "--query", "namespaces[*].namespaceName",
            "--output", "json"
        ])
        
        if ns_result:
            namespaces = {}
            for ns_name in ns_result:
                details = self.get_namespace_details(ns_name)
                namespaces[ns_name] = details
            
            with self.state_lock:
                self.namespaces = namespaces
        
        # Check for issues
        self.check_issues()
    
    def background_updater(self):
        """Background thread for AWS updates"""
        while not self.stop_thread.is_set():
            self.update_workgroups()
            self.stop_thread.wait(self.refresh_interval)
    
    def draw_header(self, stdscr, width):
        """Draw header with title and stats"""
        # Title
        title = "⚡ REDSHIFT SERVERLESS WORKGROUP MONITOR ⚡"
        x = (width - len(title)) // 2
        stdscr.attron(curses.color_pair(4) | curses.A_BOLD)
        stdscr.addstr(1, max(0, x), title[:width])
        stdscr.attroff(curses.color_pair(4) | curses.A_BOLD)
        
        # Stats line
        elapsed = datetime.now() - self.start_time
        minutes = int(elapsed.total_seconds() // 60)
        seconds = int(elapsed.total_seconds() % 60)
        
        with self.state_lock:
            total = len(self.workgroups)
            available = sum(1 for w in self.workgroups.values() if w['status'] == 'AVAILABLE')
            creating = sum(1 for w in self.workgroups.values() if w['status'] == 'CREATING')
            modifying = sum(1 for w in self.workgroups.values() if w['status'] == 'MODIFYING')
        
        stats = f"◷ {minutes:02d}:{seconds:02d} │ Total: {total} │ ✓ Available: {available} │ ↻ Creating: {creating} │ ⚙ Modifying: {modifying}"
        stdscr.addstr(3, 2, stats[:width-2])
    
    def draw_workgroups_table(self, stdscr, start_y, height, width):
        """Draw the workgroups table"""
        # Header
        header = "Workgroup                  Status      Namespace         RPUs    Age   Endpoint"
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(start_y, 2, header[:width-2])
        stdscr.attroff(curses.A_BOLD)
        stdscr.addstr(start_y + 1, 2, "─" * min(78, width-4))
        
        # Table content
        y = start_y + 2
        max_rows = height - start_y - 8  # Leave room for bottom sections
        
        with self.state_lock:
            workgroups_list = list(self.workgroups.items())
        
        # Handle scrolling
        visible_workgroups = workgroups_list[self.scroll_offset:self.scroll_offset + max_rows]
        
        for idx, (name, details) in enumerate(visible_workgroups):
            if y >= height - 6:
                break
            
            # Highlight selected row
            if idx + self.scroll_offset == self.selected_row:
                stdscr.attron(curses.A_REVERSE)
            
            # Status with color
            status = details['status']
            if status == 'AVAILABLE':
                status_str = "✓ AVAILABLE"
                color = curses.color_pair(2)  # Green
            elif status == 'CREATING':
                status_str = "↻ CREATING "
                color = curses.color_pair(4)  # Cyan
            elif status == 'MODIFYING':
                status_str = "⚙ MODIFYING"
                color = curses.color_pair(3)  # Yellow
            else:
                status_str = f"✗ {status[:9]}"
                color = curses.color_pair(1)  # Red
            
            # Format row
            name_display = name[:25].ljust(25)
            namespace = details['namespace'][:15].ljust(15)
            capacity = f"{details['baseCapacity']:3d}" if details['baseCapacity'] else "  -"
            age = details['age'][:5].ljust(5)
            endpoint = details['endpoint'][:30] if details['endpoint'] != 'N/A' else '-'
            
            # Draw row
            stdscr.addstr(y, 2, name_display)
            
            stdscr.attron(color)
            stdscr.addstr(y, 28, status_str)
            stdscr.attroff(color)
            
            stdscr.addstr(y, 40, namespace)
            stdscr.addstr(y, 56, capacity)
            stdscr.addstr(y, 62, age)
            stdscr.addstr(y, 68, endpoint[:width-70] if width > 70 else "")
            
            if idx + self.scroll_offset == self.selected_row:
                stdscr.attroff(curses.A_REVERSE)
            
            y += 1
        
        return y
    
    def draw_details_panel(self, stdscr, start_y, height, width):
        """Draw detailed info for selected workgroup"""
        with self.state_lock:
            workgroups_list = list(self.workgroups.items())
            if self.selected_row < len(workgroups_list):
                name, details = workgroups_list[self.selected_row]
            else:
                return start_y
        
        # Details header
        stdscr.attron(curses.A_BOLD)
        stdscr.addstr(start_y, 2, f"Selected: {name}")
        stdscr.attroff(curses.A_BOLD)
        
        # Details content
        y = start_y + 1
        if details['endpoint'] != 'N/A':
            stdscr.addstr(y, 4, f"Endpoint: {details['endpoint'][:width-15]}")
            y += 1
        
        if details['enhancedVpcRouting']:
            stdscr.addstr(y, 4, "Enhanced VPC Routing: ✓")
            y += 1
        
        if details['securityGroupIds']:
            stdscr.addstr(y, 4, f"Security Groups: {', '.join(details['securityGroupIds'][:2])}")
            y += 1
        
        return y
    
    def draw_issues(self, stdscr, start_y, width):
        """Draw issues/warnings panel"""
        if not self.issues:
            return
        
        stdscr.attron(curses.color_pair(3) | curses.A_BOLD)
        stdscr.addstr(start_y, 2, "Issues:")
        stdscr.attroff(curses.color_pair(3) | curses.A_BOLD)
        
        for idx, issue in enumerate(self.issues[:3]):
            if start_y + idx + 1 < curses.LINES - 2:
                stdscr.addstr(start_y + idx + 1, 4, issue[:width-6])
    
    def draw_animation(self, stdscr, y, x):
        """Draw smooth animation indicator"""
        frames = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
        frame = frames[self.animation_frame % len(frames)]
        stdscr.attron(curses.color_pair(4))
        stdscr.addstr(y, x, frame)
        stdscr.attroff(curses.color_pair(4))
        self.animation_frame += 1
    
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
        stdscr.timeout(50)  # 20 FPS
        
        # Start background updater
        aws_thread = threading.Thread(target=self.background_updater, daemon=True)
        aws_thread.start()
        
        try:
            while True:
                height, width = stdscr.getmaxyx()
                stdscr.erase()
                
                # Draw header
                self.draw_header(stdscr, width)
                
                # Draw separator
                stdscr.addstr(4, 0, "═" * width)
                
                # Draw workgroups table
                last_y = self.draw_workgroups_table(stdscr, 5, height, width)
                
                # Draw separator
                if last_y < height - 8:
                    stdscr.addstr(last_y + 1, 0, "─" * width)
                    
                    # Draw details panel
                    detail_y = self.draw_details_panel(stdscr, last_y + 2, height, width)
                    
                    # Draw issues if any
                    if detail_y < height - 4:
                        self.draw_issues(stdscr, detail_y + 1, width)
                
                # Draw footer
                footer = " ↑↓ Navigate │ q Quit │ r Refresh "
                stdscr.addstr(height - 1, 2, footer)
                
                # Draw animation
                self.draw_animation(stdscr, height - 1, width - 4)
                
                stdscr.refresh()
                
                # Handle input
                key = stdscr.getch()
                if key == ord('q'):
                    break
                elif key == ord('r'):
                    self.update_workgroups()
                elif key == curses.KEY_UP:
                    if self.selected_row > 0:
                        self.selected_row -= 1
                        if self.selected_row < self.scroll_offset:
                            self.scroll_offset = self.selected_row
                elif key == curses.KEY_DOWN:
                    with self.state_lock:
                        max_row = len(self.workgroups) - 1
                    if self.selected_row < max_row:
                        self.selected_row += 1
                        max_visible = height - 13
                        if self.selected_row >= self.scroll_offset + max_visible:
                            self.scroll_offset = self.selected_row - max_visible + 1
                
        finally:
            self.stop_thread.set()

def main():
    monitor = WorkgroupMonitor()
    try:
        curses.wrapper(monitor.run)
    except KeyboardInterrupt:
        print("\nMonitoring stopped")

if __name__ == "__main__":
    main()