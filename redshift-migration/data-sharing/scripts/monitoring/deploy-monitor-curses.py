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
from datetime import datetime
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
            "subnets": [],
            "producer_workgroup": None,
            "consumer_workgroups": [],
            "nlb": None,
            "healthy_targets": 0,
        }
        
        # Lock status
        self.lock_status = "Unknown"
        self.lock_owner = None
        self.lock_workgroup = None
        
        # Background thread control
        self.stop_thread = threading.Event()
        
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
    
    def check_lock_status(self):
        """Check atomic lock status"""
        lock_dir = Path("/tmp/redshift-consumer-lock.d/lock")
        try:
            if lock_dir.exists():
                owner = (lock_dir / "owner").read_text().strip()
                workgroup = (lock_dir / "workgroup").read_text().strip()
                with self.state_lock:
                    self.lock_status = "LOCKED"
                    self.lock_owner = owner
                    self.lock_workgroup = workgroup
            else:
                with self.state_lock:
                    self.lock_status = "Available"
                    self.lock_owner = None
                    self.lock_workgroup = None
        except:
            pass
    
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
        self.check_lock_status()
        
        # Check VPC - but don't flip back to pending if we already marked it complete
        with self.state_lock:
            vpc_already_complete = self.phase_status.get("networking") == "complete"
        
        if not vpc_already_complete:
            # Only check VPC if we haven't already confirmed it exists
            vpcs = self.run_aws_command(
                "ec2", "describe-vpcs",
                f"Vpcs[?Tags[?Key=='Name' && contains(Value, '{self.project_name}')]].[VpcId]"
            )
            
            if vpcs and len(vpcs) > 0:
                with self.state_lock:
                    self.resources["vpc"] = vpcs[0][0]
                self.set_phase_status("networking", "complete")
                self.set_phase_status("security", "complete")
                
                # Get project-specific subnets
                vpc_id = vpcs[0][0]
                subnets = self.run_aws_command(
                    "ec2", "describe-subnets",
                    f"Subnets[?VpcId=='{vpc_id}'].[SubnetId]"
                )
                if subnets:
                    with self.state_lock:
                        self.resources["subnets"] = [s[0] for s in subnets[:3]]
        
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
                self.resources["producer_workgroup"] = None
                
                for wg_name, status in workgroups:
                    if status == "AVAILABLE":
                        total_available += 1
                        # Properly categorize workgroups
                        if 'producer' in wg_name.lower():
                            self.resources["producer_workgroup"] = wg_name
                        else:
                            self.resources["consumer_workgroups"].append(wg_name)
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
                "endpoints[*].[endpointName,endpointStatus]"
            )
            
            if endpoints:
                with self.state_lock:
                    active_endpoints = 0
                    creating_endpoints = 0
                    for ep_name, status in endpoints:
                        # Only count project-related endpoints
                        if self.project_name in ep_name:
                            if status == "ACTIVE":
                                active_endpoints += 1
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
                f"LoadBalancers[?LoadBalancerName=='{self.project_name}-redshift-nlb'].[State.Code]"
            )
            
            if not nlbs:
                # Fallback to contains search
                nlbs = self.run_aws_command(
                    "elbv2", "describe-load-balancers",
                    f"LoadBalancers[?contains(LoadBalancerName, '{self.project_name}')].[State.Code]"
                )
            
            if nlbs and len(nlbs) > 0:
                nlb_state = nlbs[0][0]
                with self.state_lock:
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
                                healthy = sum(1 for t in targets if t.get("TargetHealth", {}).get("State") == "healthy")
                                total = len(targets)
                                
                                with self.state_lock:
                                    self.resources["healthy_targets"] = healthy
                                
                                # Check if all targets are healthy (3 per consumer for multi-AZ)
                                expected_targets = self.consumer_count * 3
                                if healthy >= expected_targets:
                                    self.set_phase_status("targets", "complete")
                                    self.set_phase_status("health", "complete")
                                    with self.state_lock:
                                        self.deployment_complete = True
                                elif total > 0:
                                    self.set_phase_status("targets", "in_progress")
                                    if healthy > 0:
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
            self.update_deployment_status()
            self.stop_thread.wait(2)
    
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
                
                # Only do full redraw if not showing fireworks
                if not fireworks_active:
                    stdscr.erase()  # More gentle than clear, preserves terminal state
                
                # Get thread-safe state - but DON'T hold lock during rendering!
                if not fireworks_active:  # Only get state when not showing fireworks
                    with self.state_lock:
                        phase_status = self.phase_status.copy()
                        current_phase_index = self.current_phase_index
                        deployment_complete = self.deployment_complete
                        lock_status = self.lock_status
                        lock_owner = self.lock_owner
                        lock_workgroup = self.lock_workgroup
                        resources = self.resources.copy()
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
                
                stdscr.addstr(y, 2, f"◷ Elapsed: {minutes:3d}m {seconds:02d}s   🎯 Target: {self.consumer_count} consumers")
                
                # Show what's actually happening
                in_progress_phases = [p['name'] for p in PHASES if phase_status[p['key']] == 'in_progress']
                if in_progress_phases:
                    stdscr.addstr(y, 25, "▶ Active: ")
                    stdscr.attron(curses.color_pair(3))  # Yellow for in-progress
                    stdscr.addstr(', '.join(in_progress_phases))
                    stdscr.attroff(curses.color_pair(3))
                elif deployment_complete:
                    stdscr.attron(curses.color_pair(2))  # Green
                    stdscr.addstr(y, 25, "✓ All Phases Complete!")
                    stdscr.attroff(curses.color_pair(2))
                else:
                    stdscr.addstr(y, 25, f"▶ Waiting: {current_phase['name']}")
                y += 2
                
                # Lock status
                if lock_status == "LOCKED":
                    stdscr.attron(curses.color_pair(3))
                    stdscr.addstr(y, 2, f"🔒 LOCK: HELD BY {lock_owner} (creating {lock_workgroup})")
                    stdscr.attroff(curses.color_pair(3))
                elif lock_status == "Available":
                    stdscr.attron(curses.color_pair(2))
                    stdscr.addstr(y, 2, "🔓 LOCK: AVAILABLE")
                    stdscr.attroff(curses.color_pair(2))
                else:
                    stdscr.addstr(y, 2, f"🔐 LOCK: {lock_status}")
                y += 2
                
                # Progress bar
                completed = sum(1 for s in phase_status.values() if s == "complete")
                pct = int((completed / len(PHASES)) * 100)
                bar_width = min(width - 20, 60)
                filled = int((pct / 100) * bar_width)
                
                stdscr.addstr(y, 2, "Progress: [")
                stdscr.attron(curses.color_pair(4))
                stdscr.addstr("█" * filled)
                stdscr.attroff(curses.color_pair(4))
                stdscr.addstr("░" * (bar_width - filled))
                stdscr.addstr(f"] {pct}%")
                y += 2
                
                # Phases
                stdscr.addstr(y, 2, "DEPLOYMENT PHASES")
                stdscr.addstr(y, 45, "RESOURCES")
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
                    
                    # Resources column
                    if i == 0:
                        stdscr.addstr(y + i, 45, f"VPC: {'✓' if resources['vpc'] else '○'}")
                    elif i == 2:
                        stdscr.addstr(y + i, 45, f"Producer: {'✓' if resources['producer_workgroup'] else '○'}")
                    elif i == 3:
                        stdscr.addstr(y + i, 45, f"Consumers: {len(resources['consumer_workgroups'])}/{self.consumer_count}")
                    elif i == 4:
                        stdscr.addstr(y + i, 45, f"NLB: {'✓ Active' if resources['nlb'] else '○ Pending'}")
                    elif i == 5:
                        # Each consumer has 3 IPs (one per AZ), so total targets = consumers * 3
                        expected_targets = self.consumer_count * 3
                        stdscr.addstr(y + i, 45, f"Targets: {resources['healthy_targets']}/{expected_targets}")
                
                y += len(PHASES) + 1
                
                # EKG at bottom
                if y < height - 2:
                    self.draw_ekg(stdscr, height - 2, 3, min(width - 6, 40))
                    if deployment_complete:
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