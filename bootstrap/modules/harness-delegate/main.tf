# ECS Cluster for Harness Delegate
resource "aws_ecs_cluster" "harness_delegate" {
  name = "${var.delegate_name}-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = merge(var.tags, {
    Name = "${var.delegate_name}-cluster"
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "harness_delegate" {
  name              = "/ecs/${var.delegate_name}"
  retention_in_days = 30
  
  tags = merge(var.tags, {
    Name = "${var.delegate_name}-logs"
  })
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution" {
  name = "${var.delegate_name}-ecs-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (permissions for the delegate itself)
resource "aws_iam_role" "ecs_task" {
  name = "${var.delegate_name}-ecs-task-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
  
  tags = var.tags
}

# Delegate IAM Policy
resource "aws_iam_policy" "delegate_permissions" {
  name        = "${var.delegate_name}-permissions"
  description = "Permissions for Harness Delegate to manage resources"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift-serverless:*",
          "redshift:*",
          "ec2:*",
          "elasticloadbalancing:*",
          "iam:GetRole",
          "iam:PassRole",
          "iam:ListRoles",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "kms:Decrypt",
          "kms:DescribeKey",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = var.managed_resource_arns
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeRouteTables",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAvailabilityZones",
          "redshift-serverless:ListNamespaces",
          "redshift-serverless:ListWorkgroups",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "delegate_permissions" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.delegate_permissions.arn
}

# Security Group for Delegate
resource "aws_security_group" "harness_delegate" {
  name_prefix = "${var.delegate_name}-sg-"
  vpc_id      = var.vpc_id
  description = "Security group for Harness Delegate"
  
  # Outbound only - delegate needs to reach Harness SaaS and AWS APIs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(var.tags, {
    Name = "${var.delegate_name}-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "harness_delegate" {
  family                   = var.delegate_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn
  
  container_definitions = jsonencode([{
    name  = "harness-delegate"
    image = var.delegate_image
    
    environment = [
      {
        name  = "DELEGATE_NAME"
        value = var.delegate_name
      },
      {
        name  = "NEXT_GEN"
        value = "true"
      },
      {
        name  = "DELEGATE_TYPE"
        value = "DOCKER"
      },
      {
        name  = "ACCOUNT_ID"
        value = var.harness_account_id
      },
      {
        name  = "DELEGATE_TOKEN"
        value = var.delegate_token
      },
      {
        name  = "MANAGER_HOST_AND_PORT"
        value = var.harness_manager_endpoint
      },
      {
        name  = "INIT_SCRIPT"
        value = var.init_script
      }
    ]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.harness_delegate.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "delegate"
      }
    }
    
    # Health check
    healthCheck = {
      command     = ["CMD-SHELL", "test -f /opt/harness-delegate/delegate.sh || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
  
  tags = var.tags
}

# ECS Service
resource "aws_ecs_service" "harness_delegate" {
  name            = var.delegate_name
  cluster         = aws_ecs_cluster.harness_delegate.id
  task_definition = aws_ecs_task_definition.harness_delegate.arn
  desired_count   = var.replicas
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.harness_delegate.id]
    assign_public_ip = false
  }
  
  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [desired_count]
  }
  
  tags = var.tags
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "delegate" {
  count = var.enable_auto_scaling ? 1 : 0
  
  max_capacity       = var.max_replicas
  min_capacity       = var.min_replicas
  resource_id        = "service/${aws_ecs_cluster.harness_delegate.name}/${aws_ecs_service.harness_delegate.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "delegate_cpu" {
  count = var.enable_auto_scaling ? 1 : 0
  
  name               = "${var.delegate_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.delegate[0].resource_id
  scalable_dimension = aws_appautoscaling_target.delegate[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.delegate[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

data "aws_region" "current" {}