variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "organization" {
  description = "Organization name for resource naming"
  type        = string
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "airline"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Networking Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway to reduce costs"
  type        = bool
  default     = false
}

# Harness Delegate Variables
variable "harness_account_id" {
  description = "Your Harness account ID"
  type        = string
  sensitive   = true
}

variable "harness_delegate_token" {
  description = "Delegate token from Harness platform"
  type        = string
  sensitive   = true
}

variable "delegate_cpu" {
  description = "CPU units for delegate (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "1024"
}

variable "delegate_memory" {
  description = "Memory for delegate in MiB"
  type        = string
  default     = "2048"
}

variable "delegate_replicas" {
  description = "Number of delegate replicas for HA"
  type        = number
  default     = 2
}

variable "delegate_image" {
  description = "Docker image for Harness delegate"
  type        = string
  default     = "harness/delegate:latest"
}

# Bastion Host Variables
variable "enable_bastion" {
  description = "Enable bastion host for debugging"
  type        = bool
  default     = false
}

variable "bastion_allowed_ips" {
  description = "List of IPs allowed to SSH to bastion"
  type        = list(string)
  default     = []
}

variable "bastion_key_name" {
  description = "EC2 key pair name for bastion access"
  type        = string
  default     = ""
}

# Auto-scaling Variables
variable "min_replicas" {
  description = "Minimum number of delegate replicas for auto-scaling"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of delegate replicas for auto-scaling"
  type        = number
  default     = 4
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the delegate"
  type        = bool
  default     = true
}