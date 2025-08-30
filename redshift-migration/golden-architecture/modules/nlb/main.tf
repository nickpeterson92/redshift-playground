# Network Load Balancer for distributing queries across consumer workgroups
resource "aws_lb" "redshift_nlb" {
  name               = "${var.project_name}-redshift-nlb"
  internal           = true  # Internal NLB for Redshift access
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  
  # Attach security groups to the NLB (supported since late 2023)
  # This controls who can send traffic TO the load balancer
  security_groups    = var.security_group_ids

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true
  
  # Enable client IP preservation (default for IP targets)
  # Security groups will still work correctly with this enabled
  preserve_host_header = false  # Not applicable for NLB

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-nlb"
      Environment = var.environment
      Purpose     = "redshift-query-distribution"
    }
  )
}

# Target group for Redshift consumers (port 5439)
# Must use IP targets since Redshift endpoints are DNS names
# Note: The targets (consumer workgroups) have their own security groups
# that only allow traffic from the NLB security group, ensuring all
# traffic flows through the load balancer
resource "aws_lb_target_group" "redshift_consumers" {
  name        = "${var.project_name}-consumers"
  port        = 5439
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # IP targets for Redshift VPC endpoints
  
  # Client IP preservation is enabled by default for IP targets
  # The consumer security groups reference the NLB security group
  # to ensure traffic still flows through the NLB even with
  # client IP preservation enabled

  # Health check for Redshift
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    protocol            = "TCP"
    port                = "5439"
  }

  # Deregistration delay for connection draining
  deregistration_delay = 60

  # Stickiness for session persistence (optional)
  stickiness {
    enabled = true
    type    = "source_ip"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-redshift-consumers"
      Environment = var.environment
    }
  )
}

# Listener for Redshift connections
resource "aws_lb_listener" "redshift" {
  load_balancer_arn = aws_lb.redshift_nlb.arn
  port              = "5439"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redshift_consumers.arn
  }
}

# Manage target group attachments via script to avoid Terraform lifecycle issues
# This allows seamless addition/removal of consumers without recreating attachments
resource "terraform_data" "manage_targets" {
  triggers_replace = {
    consumer_count = var.consumer_count
    target_group = aws_lb_target_group.redshift_consumers.id
    # Trigger update when endpoints change
    endpoints_hash = md5(jsonencode(var.consumer_endpoints))
  }

  # Update targets after any change
  provisioner "local-exec" {
    command = "${path.root}/scripts/deployment/update-nlb-targets.sh '${var.project_name}' '${data.aws_region.current.name}'"
  }
  
  depends_on = [aws_lb_target_group.redshift_consumers]
}

# Data source for current region
data "aws_region" "current" {}