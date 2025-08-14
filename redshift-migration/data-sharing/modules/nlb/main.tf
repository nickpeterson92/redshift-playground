# Network Load Balancer for distributing queries across consumer workgroups
resource "aws_lb" "redshift_nlb" {
  name               = "${var.project_name}-redshift-nlb"
  internal           = true  # Internal NLB for Redshift access
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-redshift-nlb"
    Environment = var.environment
    Purpose     = "redshift-query-distribution"
  }
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

  tags = {
    Name        = "${var.project_name}-redshift-consumers"
    Environment = var.environment
  }
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

# Target group attachments using private IPs
# Using static count based on consumer_count to avoid dynamic issues
resource "aws_lb_target_group_attachment" "consumer_attachments" {
  count = var.consumer_count

  target_group_arn = aws_lb_target_group.redshift_consumers.arn
  # Use try() to handle cases where endpoints might not exist yet
  target_id        = try(var.consumer_endpoints[count.index].address, "10.0.0.${count.index + 1}")
  port             = try(var.consumer_endpoints[count.index].port, 5439)

  depends_on = [aws_lb_target_group.redshift_consumers]
  
  lifecycle {
    create_before_destroy = true
    # Ignore changes to target_id during destroy
    ignore_changes = [target_id]
  }
}