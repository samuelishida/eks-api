# Network — RDS SG (pod-SG-scoped), pod-SG ALB rule, VPC endpoints, ACM cert (prod).

module "network" {
  source = "../../modules/network"

  name                  = var.name
  env                   = var.env_name
  region                = var.region
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  pod_security_group_id = module.eks.pod_security_group_id
  private_subnets       = module.vpc.private_subnets
  route_table_ids       = module.vpc.route_table_ids

  create_acm_cert = true
  acm_domain      = var.acm_domain
}
