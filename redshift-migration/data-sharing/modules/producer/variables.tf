variable "namespace_name" {
  description = "Name for the Redshift Serverless namespace"
  type        = string
}

variable "database_name" {
  description = "Name of the database"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "base_capacity" {
  description = "Base capacity for the workgroup in RPUs"
  type        = number
  default     = 8
}

variable "max_capacity" {
  description = "Maximum capacity for the workgroup in RPUs"
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

variable "project" {
  description = "Project name"
  type        = string
}

variable "s3_bucket_prefix" {
  description = "S3 bucket prefix for data access"
  type        = string
  default     = "redshift-data"
}

variable "publicly_accessible" {
  description = "Whether workgroup is publicly accessible"
  type        = bool
  default     = false
}