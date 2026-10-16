# ECR — repository with scan-on-push + lifecycle.

module "ecr" {
  source = "../../modules/ecr"

  name = "${var.name}-api-${var.env_name}"
  env  = var.env_name
}
