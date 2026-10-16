# Monitoring (Inc 8) — dev: lenient thresholds.
#
# The ALB + target group are created at runtime by the Load Balancer Controller
# (Inc 6); fill CloudWatch ALB/target-group dimension suffixes after first sync
# alarm has real dimensions.
module "monitoring" {
  source = "../../modules/monitoring"

  name                       = "${var.name}-${var.env_name}"
  env                        = var.env_name
  sns_email                  = var.alert_email
  cluster_name               = module.eks.cluster_name
  rds_instance_identifier    = module.rds.identifier
  asg_name                   = module.eks.asg_names["node"].asg_names[0]
  alb_name                   = ""
  target_group_name          = ""
  alb_5xx_threshold          = 20
  rds_cpu_threshold          = 90
  rds_free_storage_threshold = 5368709120
  node_count_threshold       = 1
  cp_5xx_threshold           = 5
}
