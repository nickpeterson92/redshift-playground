# General Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Network Configuration
variable "allowed_ip" {
  description = "IP address allowed to SSH to Test Drive instance"
  type        = string
  default     = "71.231.5.129/32"
}

# EC2 Configuration
variable "test_drive_instance_type" {
  description = "Instance type for Test Drive EC2 (m5.8xlarge recommended for production)"
  type        = string
  default     = "t3.large"  # Use smaller instance for dev/test
}

# Redshift Configuration
# These values should match your traditional deployment
variable "database_name" {
  description = "Name of the Redshift database (must match traditional deployment)"
  type        = string
  default     = "mydb"
}

variable "master_username" {
  description = "Master username for Redshift clusters (must match traditional deployment)"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password for Redshift clusters (must match traditional deployment)"
  type        = string
  sensitive   = true
  # Intentionally no default - must be explicitly provided to ensure it matches
}