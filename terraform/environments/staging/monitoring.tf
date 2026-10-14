# Monitoring (Inc 8) — staging: middle thresholds.
#
# The ALB + target group are created at runtime by the Load Balancer Controller
# (Inc 6); fill alb_name / target_group_arn after the first sync so the ALB 5xx
# alarm has real dimensions.
module "monitoring" {
  source = "../../modules/monitoring"

  name                       = var.name
  env                        = var.env_name
  sns_email                  = ""
  cluster_name               = module.eks.cluster_name
  rds_instance_identifier    = module.rds.identifier
  asg_name                   = module.eks.asg_names["node"].asg_names[0]
  alb_name                   = ""
  target_group_arn           = ""
  alb_5xx_threshold          = 10
  rds_cpu_threshold          = 85
  rds_free_storage_threshold = 107374182400
  node_count_threshold       = 1
  cp_error_threshold         = 0.01
}
