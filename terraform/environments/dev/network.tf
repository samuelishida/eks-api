# Network — RDS SG (workload-node-scoped), ALB target rule, VPC endpoints (no ACM in dev).

module "network" {
  source = "../../modules/network"

  name                            = "${var.name}-${var.env_name}"
  env                             = var.env_name
  region                          = var.region
  vpc_id                          = module.vpc.vpc_id
  vpc_cidr                        = var.vpc_cidr
  workload_node_security_group_id = module.eks.workload_node_security_group_id
  private_subnets                 = module.vpc.private_subnets
  route_table_ids                 = module.vpc.route_table_ids

  create_acm_cert = false
  acm_domain      = ""
}
