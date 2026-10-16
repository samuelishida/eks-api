module "lbc" {
  source = "../../modules/lbc"

  name              = "${var.name}-${var.env_name}"
  policy_name       = "${var.name}-${var.env_name}-lbc-policy"
  env               = var.env_name
  oidc_provider_arn = module.eks.oidc_provider_arn
}

output "lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.lbc.role_arn
}
