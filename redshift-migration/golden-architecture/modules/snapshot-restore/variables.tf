# Variables for Snapshot Restore Module

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "producer_endpoint" {
  description = "Producer workgroup endpoint address"
  type        = string
}

variable "producer_namespace_id" {
  description = "Producer namespace ID (used for triggers)"
  type        = string
}

variable "consumer_configs" {
  description = "Map of consumer configurations (kept for compatibility, not used)"
  type = map(object({
    namespace_id = string
    endpoint     = string
  }))
  default = {}
}

variable "master_username" {
  description = "Master username (kept for compatibility, not used)"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password (kept for compatibility, not used)"
  type        = string
  default     = ""
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

variable "restore_from_snapshot" {
  description = "Whether to restore from an existing snapshot"
  type        = bool
  default     = false
}

variable "snapshot_identifier" {
  description = "The identifier of the snapshot to restore"
  type        = string
  default     = ""
}

variable "force_restore" {
  description = "Force re-restoration of snapshot"
  type        = bool
  default     = false
}