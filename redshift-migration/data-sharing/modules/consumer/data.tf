# External data source to get private IPs from endpoint access
# Workaround for https://github.com/hashicorp/terraform-provider-aws/issues/39998
data "external" "endpoint_ips" {
  program = ["bash", "${path.module}/../../scripts/deployment/get-endpoint-ips.sh"]
  
  query = {
    endpoint_name = aws_redshiftserverless_endpoint_access.consumer.endpoint_name
    region        = var.aws_region
  }
  
  depends_on = [aws_redshiftserverless_endpoint_access.consumer]
}

locals {
  # Parse the comma-separated IPs into a list
  endpoint_ips = split(",", data.external.endpoint_ips.result.ips)
}