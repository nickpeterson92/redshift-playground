# Network Load Balancer for distributing queries across consumer workgroups
resource "aws_lb" "redshift_nlb" {
  name               = "${var.project_name}-redshift-nlb"
  internal           = true  # Internal NLB for Redshift access
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true

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
resource "aws_lb_target_group" "redshift_consumers" {
  name        = "${var.project_name}-consumers"
  port        = 5439
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # Changed from default "instance" to "ip"

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
resource "null_resource" "manage_targets" {
  triggers = {
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