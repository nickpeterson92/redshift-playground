# Create Redshift-managed VPC endpoint for stable IP addresses
resource "aws_redshiftserverless_endpoint_access" "consumer" {
  endpoint_name   = "${var.workgroup_name}-endpoint"
  workgroup_name  = aws_redshiftserverless_workgroup.consumer.workgroup_name
  subnet_ids      = var.subnet_ids
  
  vpc_security_group_ids = [var.security_group_id]
  
  depends_on = [aws_redshiftserverless_workgroup.consumer]
}