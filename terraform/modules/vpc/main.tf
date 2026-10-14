# VPC module — wraps terraform-aws-modules/vpc/aws.
#
# Providers are configured at the environment root, never here.
#
# Layout: one public + one private subnet per AZ (IPv4 only). A single shared
# NAT gateway by default (cost-effective); `per_az_nat = true` (prod) creates
# one NAT gateway per AZ instead.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7.3"

  name = "${var.name}-${var.env}"
  cidr = var.cidr

  azs = var.azs

  # /20s: public = first half of the space, private = second half.
  public_subnets  = [for i in range(length(var.azs)) : cidrsubnet(var.cidr, 4, i)]
  private_subnets = [for i in range(length(var.azs)) : cidrsubnet(var.cidr, 4, i + length(var.azs))]

  enable_nat_gateway     = true
  single_nat_gateway     = !var.per_az_nat
  one_nat_gateway_per_az = var.per_az_nat

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-${var.env}"
    Env  = var.env
  }
}
