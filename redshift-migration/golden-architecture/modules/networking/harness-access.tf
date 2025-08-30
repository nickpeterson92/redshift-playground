# Security group rules to allow Harness delegate access for CI/CD data sharing operations

# Option 1: Pass the Harness delegate security group ID as a variable
# Option 2: Use data source to find it (below)

# Get the Harness delegate security group from bootstrap
# The security group was created with name prefix pattern
data "aws_security_groups" "harness_delegate" {
  filter {
    name   = "group-name"
    values = ["nicks-org-dev-delegate-sg-*"]
  }
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  # Use the first (and should be only) security group found
  harness_delegate_sg_id = length(data.aws_security_groups.harness_delegate.ids) > 0 ? data.aws_security_groups.harness_delegate.ids[0] : ""
}

# Allow Harness delegate to access consumer workgroups directly
# Required for running data sharing commands in CI/CD pipelines
resource "aws_security_group_rule" "consumer_from_harness" {
  count                    = local.harness_delegate_sg_id != "" ? 1 : 0
  type                     = "ingress"
  from_port                = 5439
  to_port                  = 5439
  protocol                 = "tcp"
  source_security_group_id = local.harness_delegate_sg_id
  security_group_id        = aws_security_group.consumer.id
  description              = "Harness delegate access for data sharing commands"
}

# Allow Harness delegate to access producer cluster directly
# Required for creating datashares and granting permissions
resource "aws_security_group_rule" "producer_from_harness" {
  count                    = local.harness_delegate_sg_id != "" ? 1 : 0
  type                     = "ingress"
  from_port                = 5439
  to_port                  = 5439
  protocol                 = "tcp"
  source_security_group_id = local.harness_delegate_sg_id
  security_group_id        = aws_security_group.producer.id
  description              = "Harness delegate access for data sharing commands"
}