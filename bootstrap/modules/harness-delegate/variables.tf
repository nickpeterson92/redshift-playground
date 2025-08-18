variable "delegate_name" {
  description = "Name of the Harness delegate"
  type        = string
}

variable "harness_account_id" {
  description = "Harness account ID"
  type        = string
}

variable "delegate_token" {
  description = "Harness delegate token"
  type        = string
  sensitive   = true
}

variable "harness_manager_endpoint" {
  description = "Harness manager endpoint"
  type        = string
  default     = "https://app.harness.io"
}

variable "delegate_image" {
  description = "Docker image for Harness delegate"
  type        = string
  default     = "harness/delegate:latest"
}

variable "vpc_id" {
  description = "VPC ID where delegate will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for delegate deployment"
  type        = list(string)
}

variable "cpu" {
  description = "CPU units for the delegate task (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "1024"
}

variable "memory" {
  description = "Memory for the delegate task in MiB"
  type        = string
  default     = "2048"
}

variable "replicas" {
  description = "Number of delegate replicas"
  type        = number
  default     = 2
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the delegate"
  type        = bool
  default     = true
}

variable "min_replicas" {
  description = "Minimum number of delegate replicas"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of delegate replicas"
  type        = number
  default     = 4
}

variable "managed_resource_arns" {
  description = "List of AWS resource ARNs that the delegate can manage"
  type        = list(string)
  default     = ["*"]
}

variable "init_script" {
  description = "Custom initialization script for the delegate"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}