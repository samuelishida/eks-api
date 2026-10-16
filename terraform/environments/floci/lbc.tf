module "lbc" {
  source = "../../modules/lbc"

  name              = var.name
  policy_name       = "eks-api-lbc-inline"
  env               = var.env_name
  oidc_provider_arn = module.eks.oidc_provider_arn
}

moved {
  from = aws_iam_role.lbc
  to   = module.lbc.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.lbc
  to   = module.lbc.aws_iam_role_policy.this
}

output "lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.lbc.role_arn
}
