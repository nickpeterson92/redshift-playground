variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where NLB will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for NLB deployment"
  type        = list(string)
}

variable "consumer_endpoints" {
  description = "List of consumer endpoint addresses and ports"
  type = list(object({
    address = string
    port    = number
  }))
  default = []
}

variable "consumer_count" {
  description = "Number of consumers for target group attachments"
  type        = number
}