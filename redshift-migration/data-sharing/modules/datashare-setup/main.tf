# Automated Data Sharing Setup Module
# ====================================
# This module automatically configures data sharing between producer and consumers
# It only runs for newly deployed consumers to avoid unnecessary reconfiguration

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Store current consumer configuration for change detection
resource "null_resource" "consumer_state" {
  for_each = var.consumer_configs

  triggers = {
    namespace_id = each.value.namespace_id
    endpoint     = each.value.endpoint
    created_at   = timestamp()
  }
}

# Setup data sharing for new consumers only
resource "null_resource" "setup_datashare" {
  # Trigger when consumer configuration changes
  triggers = {
    consumer_count     = length(var.consumer_configs)
    consumer_state     = jsonencode(var.consumer_configs)
    producer_namespace = var.producer_namespace_id
    timestamp          = timestamp()
  }

  # Wait for all resources to be ready
  depends_on = [
    null_resource.consumer_state
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Generate Terraform output JSON for the script
      cat > /tmp/tf_output_${var.environment}.json <<EOF
      {
        "producer_endpoint": {
          "value": [{"address": "${var.producer_endpoint}"}]
        },
        "producer_namespace_id": {
          "value": "${var.producer_namespace_id}"
        },
        "master_username": {
          "value": "${var.master_username}"
        },
        "master_password": {
          "value": "${var.master_password}"
        },
        "database_name": {
          "value": "${var.database_name}"
        },
        "consumer_endpoints": {
          "value": ${jsonencode([for c in var.consumer_configs : [{"address": c.endpoint}]])}
        },
        "consumer_namespace_ids": {
          "value": ${jsonencode([for c in var.consumer_configs : c.namespace_id])}
        }
      }
      EOF
      
      # Make script executable
      chmod +x ${path.module}/../../scripts/setup/setup-datashare.sh
      
      # Run setup script with new consumers only flag
      ${path.module}/../../scripts/setup/setup-datashare.sh \
        /tmp/tf_output_${var.environment}.json \
        --new-consumers-only
      
      # Clean up
      rm -f /tmp/tf_output_${var.environment}.json
    EOT

    environment = {
      AWS_REGION = var.aws_region
    }
  }
}

# Optional: Setup script for manual execution
resource "local_file" "setup_script" {
  filename = "${path.module}/../../scripts/setup/run-setup.sh"
  content  = <<-EOT
    #!/bin/bash
    # Manual Data Sharing Setup Script
    # Run this script to manually setup data sharing for all consumers
    
    terraform output -json > /tmp/terraform_output.json
    
    ${path.module}/../../scripts/setup/setup-datashare.sh \
      /tmp/terraform_output.json \
      $@
    
    rm -f /tmp/terraform_output.json
  EOT
  
  file_permission = "0755"
}