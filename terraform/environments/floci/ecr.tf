# ECR — repository with scan-on-push + lifecycle.

module "ecr" {
  source = "../../modules/ecr"

  name = "${var.name}-api"
  env  = var.env_name
}
