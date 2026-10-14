terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68.0"
    }
    random = {
      source = "hashicorp/random"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }

  # Informational only — the binding version constraints live in the `source`
  # of each module block (modules/vpc/main.tf, modules/eks/main.tf, ...).
  required_modules {
    vpc = {
      source  = "terraform-aws-modules/vpc/aws"
      version = "~> 6.7.3"
    }
    eks = {
      source  = "terraform-aws-modules/eks/aws"
      version = "~> 21.29.0"
    }
    rds = {
      source  = "terraform-aws-modules/rds/aws"
      version = "~> 7.2.2"
    }
  }
}
