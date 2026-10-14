# Floci environment — local AWS emulator at http://127.0.0.1:4566.
#
# No S3 backend here: state is local (terraform.tfstate), intentionally.
#
# Notes:
# (a) Alternative to inline keys: use `AWS_PROFILE=floci` (a profile in
#     ~/.aws/credentials pointing at the emulator) and drop the inline
#     access_key/secret_key from the provider block below.
# (b) `FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true` must be set for the
#     k3s cluster Floci creates (EKS has no default storage class; without
#     it, PVCs from helm/ArgoCD never bind).
# (c) The `--version` CLI flag on `aws eks ...` is a global flag — pass any
#     EKS `--version` via `--cli-input-json` instead.

provider "aws" {
  region     = var.region
  access_key = var.floci_access_key
  secret_key = var.floci_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true

  endpoints {
    eks = "http://127.0.0.1:4566"
    ecr = "http://127.0.0.1:4566"
    rds = "http://127.0.0.1:4566"
    ec2 = "http://127.0.0.1:4566"
    kms = "http://127.0.0.1:4566"
    sts = "http://127.0.0.1:4566"
    s3  = "http://127.0.0.1:4566"
  }
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
