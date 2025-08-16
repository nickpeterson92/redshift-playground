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

variable "create_vpc" {
  description = "Whether to create a new VPC (true) or use existing (false)"
  type        = bool
  default     = true  # Default to creating VPC since we don't need traditional anymore
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "create_subnets" {
  description = "Whether to create new subnets"
  type        = bool
  default     = true  # Default to creating subnets
}

variable "subnet_cidrs" {
  description = "CIDR blocks for the subnets (need 3 for different AZs)"
  type        = list(string)
  default     = ["10.0.0.0/23", "10.0.2.0/23", "10.0.4.0/23"]  # /23 = 512 IPs each
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
  default     = 8
}

variable "producer_max_capacity" {
  description = "Maximum capacity for producer workgroup in RPUs"
  type        = number
  default     = 128
}

variable "consumer_base_capacity" {
  description = "Base capacity for consumer workgroups in RPUs"
  type        = number
  default     = 8
}

variable "consumer_max_capacity" {
  description = "Maximum capacity for consumer workgroups in RPUs"
  type        = number
  default     = 32
}

variable "consumer_count" {
  description = "Number of generic consumer instances to create"
  type        = number
  default     = 3
}