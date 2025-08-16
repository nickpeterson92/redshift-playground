variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "allowed_ip" {
  description = "IP address allowed to SSH to the test instance"
  type        = string
  default     = "71.231.5.129/32"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "redshift_password" {
  description = "Redshift password for testing (optional - can use env var instead)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "instance_count" {
  description = "Number of test instances to deploy for stress testing"
  type        = number
  default     = 2
}