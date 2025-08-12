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
  default     = 32
}

variable "max_capacity" {
  description = "Max capacity in RPUs"
  type        = number
  default     = 128
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

variable "purpose" {
  description = "Purpose of this consumer (analytics, reporting, etc)"
  type        = string
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