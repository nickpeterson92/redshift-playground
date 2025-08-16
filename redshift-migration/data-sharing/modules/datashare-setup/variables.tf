# Variables for Data Sharing Setup Module

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "producer_endpoint" {
  description = "Producer workgroup endpoint address"
  type        = string
}

variable "producer_namespace_id" {
  description = "Producer namespace ID"
  type        = string
}

variable "consumer_configs" {
  description = "Map of consumer configurations"
  type = map(object({
    namespace_id = string
    endpoint     = string
  }))
}

variable "master_username" {
  description = "Master username for database access"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password for database access"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "airline_dw"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}