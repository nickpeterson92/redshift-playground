# Consumer serverless workgroup module - handles read operations

# Sequential creation controller using null_resource
resource "null_resource" "creation_controller" {
  # This ensures sequential creation by using a global lock file
  provisioner "local-exec" {
    command = <<-EOT
      LOCK_FILE="/tmp/redshift-consumer-lock"
      MAX_WAIT=300  # 5 minutes max wait
      WAITED=0
      
      # Wait for lock to be available
      while [ -f "$LOCK_FILE" ] && [ $WAITED -lt $MAX_WAIT ]; do
        echo "Waiting for another consumer to finish creating (waited $${WAITED}s)..."
        sleep 10
        WAITED=$((WAITED + 10))
      done
      
      # Create our lock
      echo "${var.namespace_name}" > "$LOCK_FILE"
      
      # Keep lock for creation duration (AWS needs time to process)
      # 3 minutes to ensure AWS fully completes each workgroup
      sleep 180
      
      # Release lock
      rm -f "$LOCK_FILE"
    EOT
  }
}

# IAM role for consumer
resource "aws_iam_role" "consumer" {
  name = "${var.namespace_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift-serverless.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name        = "${var.namespace_name}-role"
    Environment = var.environment
    Type        = "generic-consumer"
  }
  
  depends_on = [null_resource.creation_controller]
}

# Attach managed policy
resource "aws_iam_role_policy_attachment" "consumer" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRedshiftAllCommandsFullAccess"
}

# S3 access for reading data
resource "aws_iam_role_policy" "s3_read" {
  name = "${var.namespace_name}-s3-read"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_prefix}-*/*",
          "arn:aws:s3:::${var.s3_bucket_prefix}-*"
        ]
      }
    ]
  })
}

# Serverless namespace
resource "aws_redshiftserverless_namespace" "consumer" {
  namespace_name      = var.namespace_name
  db_name            = var.database_name
  admin_username     = var.admin_username
  admin_user_password = var.admin_password
  
  iam_roles = [aws_iam_role.consumer.arn]

  tags = {
    Name        = var.namespace_name
    Environment = var.environment
    Type        = "generic-consumer"
    Role        = "consumer"
  }
  
  log_exports = [     "connectionlog",     "useractivitylog",     "userlog",   ]
  depends_on = [null_resource.creation_controller]
}

# Serverless workgroup
resource "aws_redshiftserverless_workgroup" "consumer" {
  namespace_name = aws_redshiftserverless_namespace.consumer.namespace_name
  workgroup_name = var.workgroup_name

  base_capacity = var.base_capacity
  max_capacity  = var.max_capacity
  
  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]
  
  publicly_accessible  = var.publicly_accessible
  enhanced_vpc_routing = true

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }

  config_parameter {
    parameter_key   = "search_path"
    parameter_value = "$user, public, ${var.database_name}_shared"
  }

  config_parameter {
    parameter_key   = "max_query_execution_time"
    parameter_value = tostring(var.max_query_execution_time)
  }

  tags = {
    Name        = var.workgroup_name
    Environment = var.environment
    Type        = "generic-consumer"
    Role        = "consumer"
  }
  
  lifecycle {
    ignore_changes = [config_parameter]
  }
}