# General Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Cluster Configuration
variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "mydb"
}

variable "master_username" {
  description = "Master username for the clusters"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password for the clusters"
  type        = string
  sensitive   = true
}

# Producer Cluster Configuration
variable "node_type" {
  description = "Node type for the producer cluster"
  type        = string
  default     = "ra3.xlplus"
}

variable "cluster_type" {
  description = "Cluster type for the producer cluster"
  type        = string
  default     = "single-node"
}

variable "number_of_nodes" {
  description = "Number of nodes for the producer cluster"
  type        = number
  default     = 1
}

# Consumer Cluster Configuration
variable "consumer_node_type" {
  description = "Node type for consumer clusters"
  type        = string
  default     = "ra3.xlplus"
}

variable "consumer_cluster_type" {
  description = "Cluster type for consumer clusters"
  type        = string
  default     = "single-node"
}

variable "consumer_number_of_nodes" {
  description = "Number of nodes for consumer clusters"
  type        = number
  default     = 1
}

# Security Configuration
variable "allowed_ip" {
  description = "IP address allowed to connect to Redshift"
  type        = string
  default     = "71.231.5.129/32"
}

variable "publicly_accessible" {
  description = "Make clusters publicly accessible"
  type        = bool
  default     = false
}

variable "encrypt_cluster" {
  description = "Enable encryption for clusters"
  type        = bool
  default     = false
}

# Snapshot Configuration
variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying clusters"
  type        = bool
  default     = true
}

variable "snapshot_retention_days" {
  description = "Number of days to retain automated snapshots"
  type        = number
  default     = 1
}

# Maintenance Configuration
variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

# Logging Configuration
variable "enable_logging" {
  description = "Enable Redshift cluster logging"
  type        = bool
  default     = false
}

variable "logging_bucket_name" {
  description = "S3 bucket for Redshift logs (leave empty to disable logging)"
  type        = string
  default     = ""
}