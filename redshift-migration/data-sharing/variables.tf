variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name to prefix resources"
  type        = string
  default     = "airline"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "redshift-vpc"
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "airline_dw"
}

variable "master_username" {
  description = "Master username for Redshift"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "master_password" {
  description = "Master password for Redshift"
  type        = string
  sensitive   = true
}

variable "allowed_ip" {
  description = "IP address allowed to connect"
  type        = string
  default     = "71.231.5.129/32"
}

variable "producer_base_capacity" {
  description = "Base capacity for producer workgroup in RPUs"
  type        = number
  default     = 32
}

variable "producer_max_capacity" {
  description = "Maximum capacity for producer workgroup in RPUs"
  type        = number
  default     = 256
}

variable "enable_datascience_consumer" {
  description = "Enable data science consumer workgroup"
  type        = bool
  default     = false
}