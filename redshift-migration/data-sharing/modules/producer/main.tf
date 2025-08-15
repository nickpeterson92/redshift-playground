# Producer serverless module - handles all write operations

# Sequential creation controller with atomic locking
resource "null_resource" "creation_controller" {
  # This ensures sequential creation using atomic lock operations
  provisioner "local-exec" {
    command = "${path.module}/sequential_create.sh '${var.namespace_name}' '${var.namespace_name}-workgroup'"
  }
  
  # Trigger on any variable change
  triggers = {
    namespace = var.namespace_name
  }
}

# KMS key for encryption
resource "aws_kms_key" "redshift" {
  description = "KMS key for Redshift producer encryption"
  
  tags = {
    Name        = "${var.namespace_name}-kms"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "redshift" {
  name          = "alias/${var.namespace_name}"
  target_key_id = aws_kms_key.redshift.key_id
}

# IAM role for producer
resource "aws_iam_role" "producer" {
  name = "${var.namespace_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name        = "${var.namespace_name}-role"
    Environment = var.environment
  }
}

# S3 access for COPY/UNLOAD
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.namespace_name}-s3-policy"
  role = aws_iam_role.producer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_prefix}-*/*",
          "arn:aws:s3:::${var.s3_bucket_prefix}-*"
        ]
      }
    ]
  })
}

# Redshift Serverless namespace
resource "aws_redshiftserverless_namespace" "producer" {
  namespace_name      = var.namespace_name
  db_name             = var.database_name
  admin_username      = var.master_username
  admin_user_password = var.master_password
  kms_key_id          = aws_kms_key.redshift.arn
  iam_roles           = [aws_iam_role.producer.arn]

  tags = {
    Name        = var.namespace_name
    Environment = var.environment
    Role        = "producer"
    Project     = var.project
  }
  
  depends_on = [null_resource.creation_controller]
}

# Redshift Serverless workgroup
resource "aws_redshiftserverless_workgroup" "producer" {
  namespace_name = aws_redshiftserverless_namespace.producer.namespace_name
  workgroup_name = "${var.namespace_name}-workgroup"
  
  # Compute configuration
  base_capacity = var.base_capacity
  max_capacity  = var.max_capacity
  
  # Network configuration
  subnet_ids             = var.subnet_ids
  security_group_ids     = [var.security_group_id]
  publicly_accessible    = var.publicly_accessible
  
  # Enhanced VPC routing for better performance
  enhanced_vpc_routing = true
  
  tags = {
    Name        = "${var.namespace_name}-workgroup"
    Environment = var.environment
    Role        = "producer"
    Project     = var.project
  }
}

# Wait for workgroup to be fully available before allowing consumers to start
resource "null_resource" "wait_for_availability" {
  depends_on = [aws_redshiftserverless_workgroup.producer]
  
  provisioner "local-exec" {
    command = "${path.module}/wait_for_workgroup.sh '${var.namespace_name}-workgroup' '${var.namespace_name}'"
  }
  
  # Trigger on workgroup changes
  triggers = {
    workgroup_id = aws_redshiftserverless_workgroup.producer.id
  }
}