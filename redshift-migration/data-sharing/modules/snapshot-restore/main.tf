# Snapshot Restoration Module
# ============================
# This module runs AFTER all infrastructure is deployed
# and restores a snapshot to the producer namespace if configured.

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Restore snapshot to producer (if configured)
resource "null_resource" "restore_snapshot" {
  count = var.restore_from_snapshot ? 1 : 0

  triggers = {
    snapshot_id = var.snapshot_identifier
    namespace   = var.producer_namespace_id
    timestamp   = var.force_restore ? timestamp() : "initial"
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Extract namespace and workgroup names from endpoint
      NAMESPACE_NAME=$(echo ${var.producer_endpoint} | cut -d'-' -f1-2)
      WORKGROUP_NAME=$(echo ${var.producer_endpoint} | cut -d'.' -f1)
      
      # Make script executable
      chmod +x ${path.module}/../../scripts/deployment/restore-snapshot.sh
      
      # Run the restore script
      ${path.module}/../../scripts/deployment/restore-snapshot.sh \
        "$NAMESPACE_NAME" \
        "$WORKGROUP_NAME" \
        "${var.snapshot_identifier}" \
        "${var.aws_region}"
    EOT

    environment = {
      AWS_REGION = var.aws_region
    }
  }
}