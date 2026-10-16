output "rds_security_group_id" {
  description = "RDS security group ID (attach to the RDS instance)."
  value       = aws_security_group.rds.id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for the ALB TLS (empty when not created)."
  value       = var.create_acm_cert ? aws_acm_certificate.alb[0].arn : ""
}

output "acm_validation" {
  description = "ACM DNS validation options; create the listed CNAME records in the hosted zone."
  value       = var.create_acm_cert ? aws_acm_certificate.alb[0].domain_validation_options : []
}
