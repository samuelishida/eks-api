provider "aws" {
  region = var.region
}

module "vpc" {
  source = "../../modules/vpc"

  name       = var.name
  env        = var.env_name
  cidr       = var.vpc_cidr
  azs        = var.azs
  per_az_nat = var.per_az_nat
}

module "eks" {
  source = "../../modules/eks"

  name                = var.name
  env                 = var.env_name
  vpc_id              = module.vpc.vpc_id
  private_subnets     = module.vpc.private_subnets
  node_instance_types = var.node_instance_types
  asg_min             = var.asg_min
  asg_max             = var.asg_max
  asg_desired         = var.asg_desired
  logging             = var.cluster_log_types
}

# kubernetes provider: writes the DB-password Secret (Inc 3). On a real account,
# `terraform apply` must run from inside the VPC (private-only endpoint) — see the runbook.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
