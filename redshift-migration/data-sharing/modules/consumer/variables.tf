variable "namespace_name" {
  description = "Name of the serverless namespace"
  type        = string
}

variable "workgroup_name" {
  description = "Name of the serverless workgroup"
  type        = string
}

variable "database_name" {
  description = "Name of the database"
  type        = string
}

variable "admin_username" {
  description = "Admin username"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Admin password"
  type        = string
  sensitive   = true
}

variable "base_capacity" {
  description = "Base capacity in RPUs"
  type        = number
  default     = 8
}

variable "max_capacity" {
  description = "Max capacity in RPUs"
  type        = number
  default     = 32
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "consumer_index" {
  description = "Index number of this generic consumer instance"
  type        = number
  default     = 1
}

variable "publicly_accessible" {
  description = "Whether workgroup is publicly accessible"
  type        = bool
  default     = true
}

variable "s3_bucket_prefix" {
  description = "S3 bucket prefix for data access"
  type        = string
  default     = "redshift-data"
}

variable "max_query_execution_time" {
  description = "Max query execution time in seconds"
  type        = number
  default     = 3600  # 1 hour
}