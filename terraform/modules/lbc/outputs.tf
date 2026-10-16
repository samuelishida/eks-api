output "role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = aws_iam_role.this.arn
}
