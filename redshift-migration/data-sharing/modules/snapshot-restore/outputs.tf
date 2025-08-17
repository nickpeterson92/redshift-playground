# Outputs for Snapshot Restore Module

output "restore_complete" {
  description = "ID of the restore resource when complete"
  value       = try(null_resource.restore_snapshot[0].id, null)
}

output "snapshot_restored" {
  description = "Whether a snapshot was restored"
  value       = var.restore_from_snapshot
}

output "snapshot_identifier" {
  description = "The snapshot that was restored"
  value       = var.restore_from_snapshot ? var.snapshot_identifier : "none"
}