output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.redshift_nlb.dns_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.redshift_nlb.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.redshift_consumers.arn
}

output "nlb_connection_string" {
  description = "Connection string for the NLB"
  value       = "jdbc:redshift://${aws_lb.redshift_nlb.dns_name}:5439/dev"
}