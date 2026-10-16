# Network — RDS SG (workload-node-scoped), ALB target rule, VPC endpoints (Floci).

module "network" {
  source = "../../modules/network"

  name                            = var.name
  env                             = var.env_name
  region                          = var.region
  vpc_id                          = module.vpc.vpc_id
  vpc_cidr                        = var.vpc_cidr
  workload_node_security_group_id = module.eks.workload_node_security_group_id
  private_subnets                 = module.vpc.private_subnets
  route_table_ids                 = module.vpc.route_table_ids

  # Existing Floci state has this legacy description; its SG API ignores updates.
  # This text is metadata only; network access is node-group scoped.
  alb_ingress_rule_description = "ALB -> API pods (ip-targeting); ALB SG is runtime-created, so VPC CIDR is used"

  create_acm_cert = false
  acm_domain      = ""
}
