#!/usr/bin/env python3
"""
Ultra-smooth Redshift Deployment Monitor using curses
Direct terminal manipulation for zero jitter
"""

import curses
import time
import subprocess
import json
import os
import threading
import random
import math
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, Any, List
import sys

# Deployment phases
PHASES = [
    {"name": "VPC & Networking", "key": "networking", "icon": "🌐"},
    {"name": "Security Groups", "key": "security", "icon": "🔒"},
    {"name": "Producer Namespace", "key": "producer_namespace", "icon": "📝"},
    {"name": "Producer Workgroup", "key": "producer_workgroup", "icon": "⚡"},
    {"name": "Consumer Namespaces", "key": "consumer_namespaces", "icon": "📋"},
    {"name": "Consumer Workgroups", "key": "consumer_workgroups", "icon": "⚡"},
    {"name": "VPC Endpoints", "key": "vpc_endpoints", "icon": "🔌"},
    {"name": "Network Load Balancer", "key": "nlb", "icon": "⚖️"},
    {"name": "Target Registration", "key": "targets", "icon": "🎯"},
    {"name": "Health Checks", "key": "health", "icon": "💚"},
]

class CursesMonitor:
    def __init__(self):
        self.start_time = datetime.now()
        self.ekg_position = 0
        self.heart_beat = 0
        
        # Config
        self.project_name = os.environ.get('PROJECT_NAME', 'airline')
        self.aws_region = os.environ.get('AWS_REGION', 'us-west-2')
        
        # Dynamically determine consumer count
        self.consumer_count = self._detect_consumer_count()
        # Log what was detected (will be visible before curses starts)
        if os.environ.get('DEBUG'):
            print(f"Detected consumer_count: {self.consumer_count}")
        
        # State with thread safety
        self.state_lock = threading.Lock()
        self.phase_status = {phase["key"]: "pending" for phase in PHASES}
        self.phase_complete_sticky = {phase["key"]: False for phase in PHASES}  # Once complete, stays complete
        self.current_phase_index = 0
        self.deployment_complete = False
        self.fireworks_shown = False
        self.fireworks_frame = 0
        self.fireworks = []  # List of active firework particles
        
        # Resources
        self.resources = {
            "vpc": None,
            "vpc_cidr": None,
            "subnets": [],
            "subnet_azs": [],  # Track availability zones
            "producer_workgroup": None,
            "producer_status": None,
            "consumer_workgroups": [],
            "consumer_statuses": {},  # Track individual workgroup statuses
            "nlb": None,
            "nlb_dns": None,
            "nlb_state": None,
            "target_group_arn": None,
            "healthy_targets": 0,
            "total_targets": 0,
            "target_states": {},  # Track individual target states
            "vpc_endpoints": [],  # Track endpoint details
            "endpoint_statuses": {},  # Track endpoint statuses
        }
        
        # Background thread control
        self.stop_thread = threading.Event()
        self.last_poll_time = datetime.now()
        self.poll_indicator = 0
        self.animation_frame = 0  # For smooth animations independent of polling
        
        # AWS credential refresh
        self.last_credential_refresh = datetime.now()
        self.credential_refresh_interval = 55 * 60  # 55 minutes in seconds
        self.credential_refresh_message = None
        self.show_refresh_message_until = None
        
        # Refresh credentials on startup to ensure we start fresh
        if os.environ.get('REFRESH_ON_START', '1') == '1':  # Default to refreshing
            self.refresh_aws_credentials()
        
    def _detect_consumer_count(self):
        """Dynamically detect the number of consumers from various sources"""
        # First, check if explicitly set via environment
        if 'CONSUMER_COUNT' in os.environ:
            return int(os.environ.get('CONSUMER_COUNT'))
        
        # Try to detect from terraform.tfvars if it exists
        # Get the script's directory and work from there
        script_dir = Path(__file__).parent.parent.parent  # Go up to data-sharing dir
        tfvars_paths = [
            'environments/dev/terraform.tfvars',  # From current directory
            'terraform.tfvars',  # From current directory
            script_dir / 'environments/dev/terraform.tfvars',  # Absolute path
            Path.cwd() / 'environments/dev/terraform.tfvars',  # From working directory
        ]
        
        for tfvars_path in tfvars_paths:
            tfvars_path = Path(tfvars_path)  # Convert to Path object
            if tfvars_path.exists():
                try:
                    with open(tfvars_path, 'r') as f:
                        content = f.read()
                        # Look for consumer_count = X pattern
                        match = re.search(r'consumer_count\s*=\s*(\d+)', content)
                        if match:
                            count = int(match.group(1))
                            # Debug logging if needed
                            if os.environ.get('DEBUG'):
                                print(f"Found consumer_count={count} in {tfvars_path}")
                            return count
                except Exception as e:
                    # Log error for debugging but continue
                    if os.environ.get('DEBUG'):
                        print(f"Error reading {tfvars_path}: {e}")
                    pass
        
        # Try to detect from AWS - count existing or planned consumer workgroups
        try:
            result = subprocess.run(
                ["aws", "redshift-serverless", "list-workgroups",
                 "--query", f"length(workgroups[?contains(workgroupName, '{self.project_name}-consumer')])",
                 "--output", "text"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                existing_count = int(result.stdout.strip())
                if existing_count > 0:
                    return existing_count
        except:
            pass
        
        # Default to 3 if we can't detect
        return 3
    
    def _set_phase_status_unsafe(self, phase_key: str, status: str):
        """Set phase status with sticky complete logic - must be called with lock held"""
        # If already marked complete and sticky, don't change it
        if self.phase_complete_sticky.get(phase_key, False):
            return
        
        # Update status
        self.phase_status[phase_key] = status
        
        # If marking as complete, set sticky flag
        if status == "complete":
            self.phase_complete_sticky[phase_key] = True
    
    def set_phase_status(self, phase_key: str, status: str):
        """Set phase status with sticky complete logic"""
        with self.state_lock:
            self._set_phase_status_unsafe(phase_key, status)
    
    
    def refresh_aws_credentials(self):
        """Refresh AWS credentials using aws-azure-login (non-blocking)"""
        try:
            # Run aws-azure-login with --no-prompt to avoid interactive prompts
            # Capture output to show feedback
            proc = subprocess.Popen(
                ["aws-azure-login", "--no-prompt"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                text=True
            )
            
            # Start a thread to read output and update status
            def read_output():
                try:
                    stdout, stderr = proc.communicate(timeout=30)
                    
                    with self.state_lock:
                        if proc.returncode == 0:
                            # Parse output for useful info
                            if "Assuming role" in stdout:
                                # Extract role info
                                import re
                                role_match = re.search(r'Assuming role (arn:aws:iam::\d+:role/[\w-]+)', stdout)
                                if role_match:
                                    self.credential_refresh_message = f"Logged in: {role_match.group(1).split('/')[-1]}"
                                else:
                                    self.credential_refresh_message = "AWS credentials refreshed"
                            else:
                                self.credential_refresh_message = "AWS credentials refreshed"
                            self.last_credential_refresh = datetime.now()
                        else:
                            self.credential_refresh_message = "Credential refresh failed"
                        
                        self.show_refresh_message_until = datetime.now() + timedelta(seconds=8)
                        
                except subprocess.TimeoutExpired:
                    with self.state_lock:
                        self.credential_refresh_message = "Credential refresh timeout"
                        self.show_refresh_message_until = datetime.now() + timedelta(seconds=5)
                except Exception as e:
                    with self.state_lock:
                        self.credential_refresh_message = f"Error: {str(e)[:30]}"
                        self.show_refresh_message_until = datetime.now() + timedelta(seconds=5)
            
            import threading
            threading.Thread(target=read_output, daemon=True).start()
            
            # Immediate feedback
            with self.state_lock:
                self.credential_refresh_message = "Refreshing AWS credentials..."
                self.show_refresh_message_until = datetime.now() + timedelta(seconds=2)
                
        except Exception as e:
            with self.state_lock:
                self.credential_refresh_message = f"Credential refresh failed: {e}"
                self.show_refresh_message_until = datetime.now() + timedelta(seconds=5)
    
    def run_aws_command(self, service: str, command: str, query: str = None) -> Any:
        """Run AWS CLI command"""
        cmd = ["aws", service, command]
        if query:
            cmd.extend(["--query", query])
        cmd.extend(["--output", "json", "--region", self.aws_region])
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout:
                return json.loads(result.stdout)
        except:
            pass
        return None
    
    def update_deployment_status(self):
        """Update deployment status in background"""
        # Update poll indicator (only if not complete)
        with self.state_lock:
            self.last_poll_time = datetime.now()
            if not self.deployment_complete:
                self.poll_indicator = (self.poll_indicator + 1) % 4
        
        # Check VPC - but don't flip back to pending if we already marked it complete
        with self.state_lock:
            vpc_already_complete = self.phase_status.get("networking") == "complete"
        
        if not vpc_already_complete:
            # Only check VPC if we haven't already confirmed it exists
            vpcs = self.run_aws_command(
                "ec2", "describe-vpcs",
                f"Vpcs[?Tags[?Key=='Name' && contains(Value, '{self.project_name}')]].[VpcId,CidrBlock]"
            )
            
            if vpcs and len(vpcs) > 0:
                vpc_id = vpcs[0][0]
                vpc_cidr = vpcs[0][1] if len(vpcs[0]) > 1 else None
                
                with self.state_lock:
                    self.resources["vpc"] = vpc_id
                    self.resources["vpc_cidr"] = vpc_cidr
                self.set_phase_status("networking", "complete")
                self.set_phase_status("security", "complete")
                
                # Get project-specific subnets with AZ info
                subnets = self.run_aws_command(
                    "ec2", "describe-subnets",
                    f"Subnets[?VpcId=='{vpc_id}'].[SubnetId,AvailabilityZone,CidrBlock]"
                )
                if subnets:
                    with self.state_lock:
                        self.resources["subnets"] = [s[0] for s in subnets[:3]]
                        self.resources["subnet_azs"] = [s[1] for s in subnets[:3] if len(s) > 1]
        
        # Check workgroups
        workgroups = self.run_aws_command(
            "redshift-serverless", "list-workgroups",
            "workgroups[*].[workgroupName,status]"
        )
        
        if workgroups:
            with self.state_lock:
                # Don't infer VPC from workgroups - they could be from a previous deployment
                
                # Count available and creating workgroups
                total_available = 0
                total_creating = 0
                
                # Clear resources first to rebuild accurately
                self.resources["consumer_workgroups"] = []
                self.resources["consumer_statuses"] = {}
                self.resources["producer_workgroup"] = None
                self.resources["producer_status"] = None
                
                for wg_name, status in workgroups:
                    # Only count project-related workgroups
                    if self.project_name in wg_name:
                        if 'producer' in wg_name.lower():
                            self.resources["producer_workgroup"] = wg_name
                            self.resources["producer_status"] = status
                        else:
                            if status == "AVAILABLE":
                                self.resources["consumer_workgroups"].append(wg_name)
                            self.resources["consumer_statuses"][wg_name] = status
                        
                        # Count status for project workgroups only
                        if status == "AVAILABLE":
                            total_available += 1
                        elif status in ["CREATING", "MODIFYING"]:
                            total_creating += 1
                
                # Track workgroup completion status
                expected_total = self.consumer_count + 1  # consumers + producer
                
                # If workgroups exist, VPC and security must be complete (and stay complete)
                if total_available > 0 or total_creating > 0:
                    # VPC and Security Groups must exist for workgroups to be created
                    self._set_phase_status_unsafe("networking", "complete")
                    self._set_phase_status_unsafe("security", "complete")
                    if not self.resources.get("vpc"):
                        self.resources["vpc"] = "inferred-from-workgroups"  # Mark as exists even if we can't find it
                
                if total_available >= expected_total:
                    # All workgroups are available
                    self._set_phase_status_unsafe("producer_namespace", "complete")
                    self._set_phase_status_unsafe("producer_workgroup", "complete")
                    self._set_phase_status_unsafe("consumer_namespaces", "complete")
                    self._set_phase_status_unsafe("consumer_workgroups", "complete")
                    # Don't mark endpoints/NLB/targets as complete here - check them separately
                elif total_creating > 0 or total_available > 0:
                    # Workgroups exist or are being created - namespaces must be complete
                    # Check if it's producer or consumer being created
                    producer_exists = False
                    consumer_available = 0
                    consumer_creating = 0
                    
                    for wg_name, status in workgroups:
                        if 'producer' in wg_name.lower():
                            if status == "CREATING":
                                self._set_phase_status_unsafe("producer_namespace", "complete")
                                self._set_phase_status_unsafe("producer_workgroup", "in_progress")
                            elif status == "AVAILABLE":
                                self._set_phase_status_unsafe("producer_namespace", "complete")
                                self._set_phase_status_unsafe("producer_workgroup", "complete")
                        else:
                            # It's a consumer workgroup
                            if status == "CREATING":
                                consumer_creating += 1
                                self._set_phase_status_unsafe("consumer_namespaces", "complete")
                            elif status == "AVAILABLE":
                                consumer_available += 1
                                self._set_phase_status_unsafe("consumer_namespaces", "complete")
                    
                    # Set consumer workgroup status based on actual state
                    if consumer_creating > 0:
                        # Any consumer still creating = in progress
                        self._set_phase_status_unsafe("consumer_workgroups", "in_progress")
                    elif consumer_available >= self.consumer_count:
                        # All expected consumers available = complete
                        self._set_phase_status_unsafe("consumer_workgroups", "complete")
                    elif consumer_available > 0:
                        # Some available but not all = in progress
                        self._set_phase_status_unsafe("consumer_workgroups", "in_progress")
        
        # Check VPC Endpoints if workgroups are complete
        if self.phase_status["consumer_workgroups"] == "complete":
            endpoints = self.run_aws_command(
                "redshift-serverless", "list-endpoint-access",
                "endpoints[*].[endpointName,endpointStatus,address]"
            )
            
            if endpoints:
                with self.state_lock:
                    active_endpoints = 0
                    creating_endpoints = 0
                    self.resources["vpc_endpoints"] = []
                    self.resources["endpoint_statuses"] = {}
                    
                    for endpoint_data in endpoints:
                        ep_name = endpoint_data[0] if len(endpoint_data) > 0 else None
                        status = endpoint_data[1] if len(endpoint_data) > 1 else None
                        address = endpoint_data[2] if len(endpoint_data) > 2 else None
                        
                        # Only count project-related endpoints
                        if ep_name and self.project_name in ep_name:
                            self.resources["endpoint_statuses"][ep_name] = {
                                "status": status,
                                "address": address
                            }
                            
                            if status == "ACTIVE":
                                active_endpoints += 1
                                self.resources["vpc_endpoints"].append(ep_name)
                            elif status == "CREATING":
                                creating_endpoints += 1
                    
                    if creating_endpoints > 0:
                        self._set_phase_status_unsafe("vpc_endpoints", "in_progress")
                    elif active_endpoints >= self.consumer_count:
                        self._set_phase_status_unsafe("vpc_endpoints", "complete")
                    else:
                        # If we have workgroups but no endpoints, mark as pending
                        self._set_phase_status_unsafe("vpc_endpoints", "pending")
        
        # Check NLB only after endpoints are complete
        with self.state_lock:
            check_nlb = self.phase_status["vpc_endpoints"] == "complete"
        
        if check_nlb:
            # Try exact name first, then contains
            nlbs = self.run_aws_command(
                "elbv2", "describe-load-balancers",
                f"LoadBalancers[?LoadBalancerName=='{self.project_name}-redshift-nlb'].[State.Code,DNSName]"
            )
            
            if not nlbs:
                # Fallback to contains search
                nlbs = self.run_aws_command(
                    "elbv2", "describe-load-balancers",
                    f"LoadBalancers[?contains(LoadBalancerName, '{self.project_name}')].[State.Code,DNSName]"
                )
            
            if nlbs and len(nlbs) > 0:
                nlb_state = nlbs[0][0]
                nlb_dns = nlbs[0][1] if len(nlbs[0]) > 1 else None
                
                with self.state_lock:
                    self.resources["nlb_state"] = nlb_state
                    self.resources["nlb_dns"] = nlb_dns
                    
                    if nlb_state == "active":
                        self.resources["nlb"] = "active"
                        self._set_phase_status_unsafe("nlb", "complete")
                    elif nlb_state in ["provisioning", "active_impaired"]:
                        self.resources["nlb"] = nlb_state
                        self._set_phase_status_unsafe("nlb", "in_progress")
                
                # Check targets - try exact name first (moved outside lock)
                tgs = self.run_aws_command(
                    "elbv2", "describe-target-groups",
                    f"TargetGroups[?TargetGroupName=='{self.project_name}-redshift-tg'].[TargetGroupArn]"
                )
                
                if not tgs:
                    # Fallback to contains search
                    tgs = self.run_aws_command(
                        "elbv2", "describe-target-groups",
                        f"TargetGroups[?contains(TargetGroupName, '{self.project_name}')].[TargetGroupArn]"
                    )
                
                if tgs and len(tgs) > 0:
                    # Pass the ARN correctly to describe-target-health
                    health_cmd = [
                        "aws", "elbv2", "describe-target-health",
                        "--target-group-arn", tgs[0][0],
                        "--output", "json"
                    ]
                    health_result = subprocess.run(health_cmd, capture_output=True, text=True, timeout=5)
                    
                    if health_result.returncode == 0 and health_result.stdout:
                        try:
                            health = json.loads(health_result.stdout)
                            if "TargetHealthDescriptions" in health:
                                targets = health["TargetHealthDescriptions"]
                                
                                # Count target states for more granular feedback
                                state_counts = {
                                    "healthy": 0,
                                    "initial": 0,
                                    "unhealthy": 0,
                                    "draining": 0,
                                    "unavailable": 0
                                }
                                
                                for t in targets:
                                    state = t.get("TargetHealth", {}).get("State", "unknown")
                                    state_counts[state] = state_counts.get(state, 0) + 1
                                
                                healthy = state_counts["healthy"]
                                initial = state_counts["initial"]
                                total = len(targets)
                                
                                with self.state_lock:
                                    self.resources["healthy_targets"] = healthy
                                    self.resources["total_targets"] = total
                                    self.resources["target_states"] = state_counts
                                
                                # Check if all targets are healthy (3 per consumer for multi-AZ)
                                expected_targets = self.consumer_count * 3
                                if healthy >= expected_targets:
                                    self.set_phase_status("targets", "complete")
                                    self.set_phase_status("health", "complete")
                                    with self.state_lock:
                                        self.deployment_complete = True
                                elif total > 0:
                                    # Targets are registering or health checking
                                    self.set_phase_status("targets", "in_progress")
                                    if healthy > 0 or initial > 0:
                                        self.set_phase_status("health", "in_progress")
                        except:
                            pass
                else:
                    # If NLB is active but no target group found, mark as in progress
                    with self.state_lock:
                        if self.resources.get("nlb") == "active":
                            self._set_phase_status_unsafe("targets", "in_progress")
        
        # Update current phase - find what's actually IN PROGRESS
        with self.state_lock:
            # First, look for any phase that's actively "in_progress"
            for i, phase in enumerate(PHASES):
                if self.phase_status[phase["key"]] == "in_progress":
                    self.current_phase_index = i
                    return  # Found active phase
            
            # If nothing is in progress, find the first pending phase
            for i, phase in enumerate(PHASES):
                if self.phase_status[phase["key"]] == "pending":
                    self.current_phase_index = i
                    return
            
            # All complete
            self.current_phase_index = len(PHASES) - 1
    
    def background_updater(self):
        """Background thread for AWS updates"""
        while not self.stop_thread.is_set():
            # Check if we need to refresh AWS credentials
            elapsed_since_refresh = (datetime.now() - self.last_credential_refresh).total_seconds()
            if elapsed_since_refresh >= self.credential_refresh_interval:
                # Refresh credentials in background
                self.refresh_aws_credentials()
            
            # Update deployment status
            self.update_deployment_status()
            
            # Adaptive polling - faster during critical phases
            with self.state_lock:
                # If deployment is complete, slow down polling significantly
                if self.deployment_complete:
                    poll_interval = 10  # Very slow polling when complete
                # Poll faster during target registration and health checks
                elif self.phase_status.get("targets") == "in_progress" or \
                     self.phase_status.get("health") == "in_progress":
                    poll_interval = 1  # Poll every second during target registration
                elif self.phase_status.get("nlb") == "in_progress":
                    poll_interval = 1.5  # Slightly faster for NLB provisioning
                elif any(status == "in_progress" for status in self.phase_status.values()):
                    poll_interval = 2  # Standard polling for other phases
                else:
                    poll_interval = 3  # Slower when nothing is happening
            
            self.stop_thread.wait(poll_interval)
    
    def draw_ekg(self, win, y, x, width):
        """Draw smooth EKG animation - athletic 60 bpm resting heart rate"""
        ekg_line = "━" * width
        
        # Heart beat controls the rhythm 
        # 60 bpm = 60 beats/60 seconds = 1 beat/second
        # At 60 FPS, that's exactly 60 frames per beat - perfect!
        beat_cycle = 60
        self.heart_beat = (self.heart_beat + 1) % beat_cycle
        
        # When heart beats strongest (frame 0), trigger a new EKG wave
        if self.heart_beat == 0:
            self.ekg_position = 0  # Start new wave from left
        
        # Create pulse at position (only if we're in a heartbeat cycle)
        if self.ekg_position < width - 2 and self.heart_beat < 45:  # Wave travels during heartbeat
            ekg_line = ekg_line[:self.ekg_position] + "╱╲" + ekg_line[self.ekg_position+2:]
            # Move the wave across the screen (nice and steady for athlete's heart)
            if self.heart_beat % 2 == 0:  # Move every other frame
                self.ekg_position = min(self.ekg_position + 2, width)
        
        # Draw with color
        win.attron(curses.color_pair(2))  # Green
        win.addstr(y, x, f"[{ekg_line[:width-2]}]")
        win.attroff(curses.color_pair(2))
        
        # Heart animation - strong and efficient like an athlete
        if self.heart_beat < 10:  # Strong beat (triggers wave) - powerful but brief
            heart = "♥"
            win.attron(curses.color_pair(1) | curses.A_BOLD)  # Bright red
        elif self.heart_beat < 40:  # Normal beat - steady and strong
            heart = "♥"
            win.attron(curses.color_pair(1))  # Red
        else:  # Resting (last 20 frames) - good recovery time
            heart = "♡"
            win.attron(curses.color_pair(1))  # Red but hollow
        
        win.addstr(y, x-2, heart)
        win.attroff(curses.color_pair(1) | curses.A_BOLD)
    
    def create_firework(self, x, y):
        """Create a simple firework burst at position"""
        colors = [1, 2, 3, 4, 5, 6, 7]  # All our color pairs
        
        particles = []
        
        # Single clean explosion - slower speed for more savoring
        for angle in range(0, 360, 15):  # 24 directions
            rad = math.radians(angle)
            speed = random.uniform(2, 4)  # Slower expansion
            
            particles.append({
                'x': x,
                'y': y,
                'fx': float(x),
                'fy': float(y),
                'vx': math.cos(rad) * speed,
                'vy': math.sin(rad) * speed * 0.5,  # Flatten vertically
                'char': '*',
                'color': random.choice(colors),
                'life': 60 + random.randint(0, 20),  # Longer life
                'fade_start': 30  # Start fading later
            })
        
        return particles
    
    def update_fireworks(self):
        """Update firework particles with smooth physics"""
        # Remove dead particles
        self.fireworks = [p for p in self.fireworks if p['life'] > 0]
        
        # Update existing particles
        for particle in self.fireworks:
            particle['life'] -= 1
            
            # Apply gentler physics for slower, more graceful movement
            particle['vy'] += 0.05  # Very light gravity
            particle['vx'] *= 0.99  # Less air resistance
            particle['vy'] *= 0.99
            
            # Update position
            particle['fx'] += particle['vx']
            particle['fy'] += particle['vy']
            
            # Convert to integer for display
            particle['x'] = int(particle['fx'])
            particle['y'] = int(particle['fy'])
        
        # Launch single firework when deployment completes
        if self.deployment_complete and not self.fireworks_shown:
            if self.fireworks_frame == 0:
                # Get terminal size from main loop
                max_y = 40
                max_x = 120
                
                # Launch ONE firework in the center
                x = max_x // 2
                y = max_y // 3
                self.fireworks.extend(self.create_firework(x, y))
            
            self.fireworks_frame += 1
            
            # Mark as shown after firework fully fades (about 4 seconds)
            if self.fireworks_frame > 120:
                self.fireworks_shown = True
    
    def draw_fireworks_optimized(self, stdscr, last_particles):
        """Optimized firework drawing - only update changed positions"""
        if not self.fireworks and not last_particles:
            return [], False
        
        max_y, max_x = stdscr.getmaxyx()
        
        # Clear old particle positions
        for old_p in last_particles:
            x, y = old_p['x'], old_p['y']
            if 0 <= x < max_x and 0 <= y < max_y:
                try:
                    stdscr.addstr(y, x, ' ')  # Clear old position
                except:
                    pass
        
        # Draw new particles
        current_particles = []
        for particle in self.fireworks:
            x, y = particle['x'], particle['y']
            if 0 <= x < max_x and 0 <= y < max_y:
                try:
                    fade_start = particle.get('fade_start', 5)
                    
                    # Simple fade effect
                    if particle['life'] > fade_start:
                        # Bright
                        stdscr.attron(curses.color_pair(particle['color']) | curses.A_BOLD)
                        stdscr.addstr(y, x, '*')
                        stdscr.attroff(curses.color_pair(particle['color']) | curses.A_BOLD)
                    else:
                        # Fading
                        stdscr.attron(curses.color_pair(particle['color']))
                        stdscr.addstr(y, x, '.')
                        stdscr.attroff(curses.color_pair(particle['color']))
                    
                    # Track current particle position
                    current_particles.append({'x': x, 'y': y})
                except:
                    pass  # Ignore out of bounds
        
        # Return current particles for next frame and whether fireworks are active
        return current_particles, len(self.fireworks) > 0
    
    def run(self, stdscr):
        """Main curses loop"""
        # Setup colors with terminal defaults
        curses.start_color()
        curses.use_default_colors()  # This preserves terminal background!
        
        # Use -1 for default background to maintain transparency
        curses.init_pair(1, curses.COLOR_RED, -1)     # Red on default bg
        curses.init_pair(2, curses.COLOR_GREEN, -1)   # Green on default bg
        curses.init_pair(3, curses.COLOR_YELLOW, -1)  # Yellow on default bg
        curses.init_pair(4, curses.COLOR_CYAN, -1)    # Cyan on default bg
        curses.init_pair(5, curses.COLOR_WHITE, -1)   # White on default bg
        curses.init_pair(6, curses.COLOR_MAGENTA, -1) # Magenta on default bg
        curses.init_pair(7, curses.COLOR_BLUE, -1)    # Blue on default bg
        
        # Configure screen
        curses.curs_set(0)  # Hide cursor
        stdscr.nodelay(1)   # Non-blocking input
        stdscr.bkgd(' ', curses.color_pair(0))  # Use default background
        stdscr.clear()
        
        # Start background updater
        aws_thread = threading.Thread(target=self.background_updater, daemon=True)
        aws_thread.start()
        
        # Track if we're in fireworks mode for optimized rendering
        fireworks_active = False
        last_drawn_particles = []
        
        try:
            while True:
                height, width = stdscr.getmaxyx()
                
                # Update animation frame for smooth animations
                self.animation_frame = (self.animation_frame + 1) % 240  # Reset every 4 seconds at 60fps
                
                # Only do full redraw if not showing fireworks
                if not fireworks_active:
                    stdscr.erase()  # More gentle than clear, preserves terminal state
                
                # Get thread-safe state - but DON'T hold lock during rendering!
                if not fireworks_active:  # Only get state when not showing fireworks
                    with self.state_lock:
                        phase_status = self.phase_status.copy()
                        current_phase_index = self.current_phase_index
                        deployment_complete = self.deployment_complete
                        resources = self.resources.copy()
                        poll_indicator = self.poll_indicator
                        last_credential_refresh = self.last_credential_refresh
                        
                        # Detect teardown/deletion states
                        teardown_mode = False
                        if (resources.get('producer_status') in ['DELETING', 'DELETED'] or
                            any(s in ['DELETING', 'DELETED'] for s in resources.get('consumer_statuses', {}).values()) or
                            resources.get('nlb_state') == 'deleting' or
                            resources.get('vpc_state') == 'deleting'):
                            teardown_mode = True
                            deployment_complete = False  # Override deployment complete during teardown
                else:
                    # During fireworks, use cached values to avoid lock contention
                    pass
                
                y = 1
                
                # Header
                header = "⚡ REDSHIFT SERVERLESS DEPLOYMENT MONITOR ⚡"
                x = (width - len(header)) // 2
                stdscr.attron(curses.color_pair(4) | curses.A_BOLD)
                stdscr.addstr(y, x, header)
                stdscr.attroff(curses.color_pair(4) | curses.A_BOLD)
                y += 2
                
                # Timer and current phase
                elapsed = datetime.now() - self.start_time
                minutes = int(elapsed.total_seconds() // 60)
                seconds = int(elapsed.total_seconds() % 60)
                current_phase = PHASES[current_phase_index]
                
                # Show polling indicator - animate smoothly based on frame, not polling
                # More frames for smoother animation
                poll_indicators = ["⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽"]
                # Update every 8 frames (~7.5 times per second) for relaxed but visible animation
                poll_frame = (self.animation_frame // 8) % len(poll_indicators)
                poll_ind = poll_indicators[poll_frame] if not deployment_complete else ""
                
                # Calculate time until next credential refresh
                cred_elapsed = (datetime.now() - last_credential_refresh).total_seconds()
                cred_remaining = max(0, (55 * 60) - cred_elapsed) / 60  # in minutes
                
                # Build the status line without overlapping elements
                status_line = f"◷ Elapsed: {minutes:3d}m {seconds:02d}s"
                stdscr.addstr(y, 2, status_line)
                
                # Show what's actually happening in the middle (with polling indicator)
                in_progress_phases = [p['name'] for p in PHASES if phase_status[p['key']] == 'in_progress']
                if teardown_mode:
                    # Show teardown status
                    stdscr.attron(curses.color_pair(1))  # Red for teardown
                    stdscr.addstr(y, 30, "⚠ Tearing Down Resources...")
                    stdscr.attroff(curses.color_pair(1))
                elif in_progress_phases:
                    # Show active phases with polling indicator
                    status_text = f"{poll_ind} Active: {', '.join(in_progress_phases)}"
                    stdscr.attron(curses.color_pair(3))  # Yellow for in-progress
                    stdscr.addstr(y, 30, status_text[:width-55])  # Truncate if too long
                    stdscr.attroff(curses.color_pair(3))
                elif deployment_complete:
                    # No polling indicator when complete
                    stdscr.attron(curses.color_pair(2))  # Green
                    stdscr.addstr(y, 30, "✓ All Phases Complete!")
                    stdscr.attroff(curses.color_pair(2))
                else:
                    # Show waiting status with gentle pulsing dots
                    # Use dots animation for "searching" feel - slower and more relaxed
                    dots = "." * ((self.animation_frame // 20) % 4)  # Update every ~third of a second
                    spaces = "   "  # Add padding so text doesn't jump around
                    status_text = f"{poll_ind} Waiting: {current_phase['name']}{dots}{spaces}"
                    stdscr.addstr(y, 30, status_text[:width-55])
                
                # Show credential refresh status on the right
                # Check if we have a refresh message to show
                refresh_msg = None
                with self.state_lock:
                    if self.show_refresh_message_until and datetime.now() < self.show_refresh_message_until:
                        refresh_msg = self.credential_refresh_message
                
                if refresh_msg:
                    # Show the refresh message temporarily
                    stdscr.attron(curses.color_pair(4) | curses.A_BOLD)
                    msg = f"🔑 {refresh_msg}"
                    stdscr.addstr(y, width - len(msg) - 2, msg)
                    stdscr.attroff(curses.color_pair(4) | curses.A_BOLD)
                elif cred_remaining > 10:
                    stdscr.attron(curses.color_pair(2))
                    stdscr.addstr(y, width - 15, f"🔑 AWS: {int(cred_remaining)}m")
                    stdscr.attroff(curses.color_pair(2))
                elif cred_remaining > 0:
                    stdscr.attron(curses.color_pair(3))
                    stdscr.addstr(y, width - 20, f"🔑 AWS: {int(cred_remaining)}m ⟳")
                    stdscr.attroff(curses.color_pair(3))
                else:
                    stdscr.attron(curses.color_pair(1))
                    stdscr.addstr(y, width - 22, "🔑 AWS: Refreshing...")
                    stdscr.attroff(curses.color_pair(1))
                y += 2
                
                # Progress bar - adjust for teardown mode
                if teardown_mode:
                    # During teardown, count how many resources still exist
                    existing_resources = 0
                    total_resources = len(PHASES)
                    
                    # Count backwards - resources that are NOT deleted
                    if resources.get('producer_status') not in ['DELETING', 'DELETED', None]:
                        existing_resources += 2  # Producer namespace + workgroup
                    if resources.get('consumer_statuses'):
                        existing_resources += sum(1 for s in resources.get('consumer_statuses', {}).values() 
                                                 if s not in ['DELETING', 'DELETED'])
                    if resources.get('nlb_state') not in ['deleting', None]:
                        existing_resources += 2  # NLB + targets
                    if resources.get('vpc_id'):
                        existing_resources += 2  # VPC + security groups
                    
                    # Calculate reverse progress
                    pct = int((existing_resources / total_resources) * 100)
                else:
                    # Normal forward progress
                    completed = sum(1 for s in phase_status.values() if s == "complete")
                    pct = int((completed / len(PHASES)) * 100)
                
                bar_width = min(width - 20, 60)
                filled = int((pct / 100) * bar_width)
                
                stdscr.addstr(y, 2, "Progress: [")
                if teardown_mode:
                    # Red/orange bar for teardown
                    stdscr.attron(curses.color_pair(1))
                    stdscr.addstr("█" * filled)
                    stdscr.attroff(curses.color_pair(1))
                else:
                    # Normal cyan bar for deployment
                    stdscr.attron(curses.color_pair(4))
                    stdscr.addstr("█" * filled)
                    stdscr.attroff(curses.color_pair(4))
                stdscr.addstr("░" * (bar_width - filled))
                stdscr.addstr(f"] {pct}%")
                y += 2
                
                # Phases
                stdscr.addstr(y, 2, "DEPLOYMENT PHASES")
                stdscr.addstr(y, 45, "RESOURCE DETAILS")
                y += 1
                stdscr.addstr(y, 2, "─" * (width - 4))
                y += 1
                
                for i, phase in enumerate(PHASES):
                    status = phase_status[phase["key"]]
                    
                    # Phase status with better indicators
                    if status == "complete":
                        stdscr.attron(curses.color_pair(2))
                        stdscr.addstr(y + i, 2, "✓")
                        stdscr.attroff(curses.color_pair(2))
                        stdscr.addstr(y + i, 4, f" {phase['name']}")
                    elif status == "in_progress":
                        # Highlight in-progress phases more clearly
                        stdscr.attron(curses.color_pair(3) | curses.A_BOLD)
                        stdscr.addstr(y + i, 2, "⟳")
                        stdscr.addstr(y + i, 4, f" {phase['name']}")
                        stdscr.addstr(y + i, 30, " ← IN PROGRESS")
                        stdscr.attroff(curses.color_pair(3) | curses.A_BOLD)
                    else:
                        stdscr.attron(curses.color_pair(5))  # Dim for pending
                        stdscr.addstr(y + i, 2, "○")
                        stdscr.addstr(y + i, 4, f" {phase['name']}")
                        stdscr.attroff(curses.color_pair(5))
                    
                    # Resources column with more details
                    if i == 0:  # VPC & Networking
                        if resources.get('vpc'):
                            vpc_info = f"VPC: {resources['vpc'][-12:]}"
                            if resources.get('vpc_cidr'):
                                vpc_info += f" ({resources['vpc_cidr']})"
                            stdscr.addstr(y + i, 45, vpc_info[:35])
                        else:
                            stdscr.addstr(y + i, 45, "VPC: ○ Pending")
                    elif i == 1:  # Security Groups
                        if resources.get('subnet_azs'):
                            azs = ', '.join(resources['subnet_azs'])
                            stdscr.addstr(y + i, 45, f"AZs: {azs[:30]}")
                    elif i == 2:  # Producer namespace
                        # Show namespace info - namespaces are created before workgroups
                        if phase_status.get('producer_namespace') == 'complete':
                            stdscr.attron(curses.color_pair(2))
                            stdscr.addstr(y + i, 45, f"Namespace: ✓ {self.project_name}-producer-ns")
                            stdscr.attroff(curses.color_pair(2))
                        else:
                            stdscr.addstr(y + i, 45, "Namespace: ○ Pending")
                    elif i == 3:  # Producer workgroup
                        if resources.get('producer_workgroup'):
                            prod_status = resources.get('producer_status', 'Unknown')
                            wg_name = resources['producer_workgroup']
                            # Show full workgroup name if it fits, otherwise truncate from beginning
                            if len(wg_name) <= 30:
                                display_name = wg_name
                            else:
                                display_name = "..." + wg_name[-27:]
                            
                            if prod_status == "AVAILABLE":
                                stdscr.attron(curses.color_pair(2))
                                stdscr.addstr(y + i, 45, f"Workgroup: ✓ {display_name}")
                                stdscr.attroff(curses.color_pair(2))
                            elif prod_status in ["DELETING", "DELETED"]:
                                stdscr.attron(curses.color_pair(1))
                                stdscr.addstr(y + i, 45, f"Workgroup: ○ {prod_status}")
                                stdscr.attroff(curses.color_pair(1))
                            else:
                                stdscr.attron(curses.color_pair(3))
                                stdscr.addstr(y + i, 45, f"Workgroup: ⟳ {prod_status}")
                                stdscr.attroff(curses.color_pair(3))
                        else:
                            stdscr.addstr(y + i, 45, "Workgroup: ○ Pending")
                    elif i == 4:  # Consumer namespaces
                        # Show namespace status
                        if phase_status.get('consumer_namespaces') == 'complete':
                            stdscr.attron(curses.color_pair(2))
                            stdscr.addstr(y + i, 45, f"Namespaces: ✓ {self.consumer_count} created")
                            stdscr.attroff(curses.color_pair(2))
                        else:
                            stdscr.addstr(y + i, 45, f"Namespaces: ○ 0/{self.consumer_count}")
                    elif i == 5:  # Consumer workgroups
                        consumer_statuses = resources.get('consumer_statuses', {})
                        available_count = sum(1 for s in consumer_statuses.values() if s == "AVAILABLE")
                        creating_count = sum(1 for s in consumer_statuses.values() if s == "CREATING")
                        
                        # Get an example consumer workgroup name if available
                        example_name = ""
                        if resources.get('consumer_workgroups') and len(resources['consumer_workgroups']) > 0:
                            first_consumer = resources['consumer_workgroups'][0]
                            if len(first_consumer) <= 20:
                                example_name = f" ({first_consumer})"
                            else:
                                example_name = f" (...{first_consumer[-17:]})"
                        
                        if creating_count > 0:
                            stdscr.attron(curses.color_pair(3))
                            stdscr.addstr(y + i, 45, f"Workgroups: {available_count}/{self.consumer_count} (⟳ {creating_count})")
                            stdscr.attroff(curses.color_pair(3))
                        elif available_count > 0:
                            color = 2 if available_count == self.consumer_count else 5
                            stdscr.attron(curses.color_pair(color))
                            display_text = f"Workgroups: {available_count}/{self.consumer_count}"
                            if example_name and len(display_text + example_name) < 45:
                                display_text += example_name
                            stdscr.addstr(y + i, 45, display_text)
                            stdscr.attroff(curses.color_pair(color))
                        else:
                            stdscr.addstr(y + i, 45, f"Workgroups: 0/{self.consumer_count}")
                    elif i == 6:  # VPC Endpoints
                        endpoint_count = len(resources.get('vpc_endpoints', []))
                        endpoint_statuses = resources.get('endpoint_statuses', {})
                        creating = sum(1 for e in endpoint_statuses.values() if e.get('status') == 'CREATING')
                        
                        if creating > 0:
                            stdscr.attron(curses.color_pair(3))
                            stdscr.addstr(y + i, 45, f"Endpoints: {endpoint_count}/{self.consumer_count} (⟳ {creating} creating)")
                            stdscr.attroff(curses.color_pair(3))
                        elif endpoint_count > 0:
                            color = 2 if endpoint_count >= self.consumer_count else 5
                            stdscr.attron(curses.color_pair(color))
                            stdscr.addstr(y + i, 45, f"Endpoints: {endpoint_count}/{self.consumer_count}")
                            stdscr.attroff(curses.color_pair(color))
                        else:
                            stdscr.addstr(y + i, 45, f"Endpoints: 0/{self.consumer_count}")
                    elif i == 7:  # NLB
                        nlb_state = resources.get('nlb_state', '')
                        if nlb_state == 'active':
                            stdscr.attron(curses.color_pair(2))
                            nlb_display = "NLB: ✓ Active"
                            if resources.get('nlb_dns'):
                                # Show last part of DNS name
                                dns_suffix = resources['nlb_dns'].split('.')[0][-20:]
                                nlb_display += f" ({dns_suffix}...)"
                            stdscr.addstr(y + i, 45, nlb_display[:35])
                            stdscr.attroff(curses.color_pair(2))
                        elif nlb_state in ['provisioning', 'active_impaired']:
                            stdscr.attron(curses.color_pair(3))
                            stdscr.addstr(y + i, 45, f"NLB: ⟳ {nlb_state}")
                            stdscr.attroff(curses.color_pair(3))
                        else:
                            stdscr.addstr(y + i, 45, "NLB: ○ Pending")
                    elif i == 8:
                        # Each consumer has 3 IPs (one per AZ), so total targets = consumers * 3
                        expected_targets = self.consumer_count * 3
                        target_states = resources.get('target_states', {})
                        
                        # Show detailed target status
                        if resources.get('total_targets', 0) > 0:
                            healthy = target_states.get('healthy', 0)
                            initial = target_states.get('initial', 0)
                            
                            if healthy == expected_targets:
                                stdscr.attron(curses.color_pair(2))
                                stdscr.addstr(y + i, 45, f"Targets: ✓ {healthy}/{expected_targets} healthy")
                                stdscr.attroff(curses.color_pair(2))
                            elif initial > 0:
                                stdscr.attron(curses.color_pair(3))
                                stdscr.addstr(y + i, 45, f"Targets: ⟳ {healthy} healthy, {initial} registering...")
                                stdscr.attroff(curses.color_pair(3))
                            else:
                                stdscr.addstr(y + i, 45, f"Targets: {healthy}/{expected_targets} healthy")
                        else:
                            stdscr.addstr(y + i, 45, f"Targets: {resources['healthy_targets']}/{expected_targets}")
                
                y += len(PHASES) + 1
                
                # EKG at bottom
                if y < height - 2:
                    self.draw_ekg(stdscr, height - 2, 3, min(width - 6, 40))
                    if teardown_mode:
                        stdscr.attron(curses.color_pair(1))
                        stdscr.addstr(height - 2, 50, "Tearing down infrastructure...")
                        stdscr.attroff(curses.color_pair(1))
                    elif deployment_complete:
                        stdscr.attron(curses.color_pair(2) | curses.A_BOLD)
                        stdscr.addstr(height - 2, 50, "Deployment Complete! 🎉")
                        stdscr.attroff(curses.color_pair(2) | curses.A_BOLD)
                    else:
                        stdscr.addstr(height - 2, 50, "Monitoring deployment...")
                
                # Handle fireworks
                if deployment_complete and not self.fireworks_shown and not fireworks_active:
                    # Start fireworks mode
                    fireworks_active = True
                
                if fireworks_active:
                    # Update fireworks
                    self.update_fireworks()
                    
                    # Draw fireworks
                    last_drawn_particles, still_active = self.draw_fireworks_optimized(stdscr, last_drawn_particles)
                    
                    # Check if fireworks are done
                    if self.fireworks_shown and len(self.fireworks) == 0:
                        fireworks_active = False
                        last_drawn_particles = []
                        # Don't erase - just let it fade naturally
                else:
                    # Normal monitoring display updates
                    last_drawn_particles = []
                
                stdscr.refresh()
                
                # Check for exit (but never auto-exit)
                if stdscr.getch() == ord('q'):
                    break
                
                # 60 FPS for smooth animation
                time.sleep(0.016)
                
        finally:
            self.stop_thread.set()

def main():
    monitor = CursesMonitor()
    try:
        curses.wrapper(monitor.run)
        if monitor.deployment_complete:
            print("\n✨ DEPLOYMENT COMPLETE! ✨")
            print("All resources deployed successfully!")
    except KeyboardInterrupt:
        print("\nMonitoring stopped by user")

if __name__ == "__main__":
    main()