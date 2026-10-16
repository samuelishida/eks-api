variable "name" {
  description = "Base name for resources."
  type        = string
}

variable "env" {
  description = "Environment name (dev/staging/prod/floci)."
  type        = string
}

variable "sns_email" {
  description = "Email address to subscribe to the alerts topic (empty = no subscription)."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "EKS cluster name (dimension for the control-plane error-rate alarm)."
  type        = string
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier (dimension for the RDS alarms)."
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling group name of the EKS managed node group (dimension for the node-count alarm)."
  type        = string
}

variable "alb_name" {
  description = "CloudWatch LoadBalancer dimension suffix (app/name/id), filled after first sync."
  type        = string
  default     = ""
}

variable "target_group_name" {
  description = "CloudWatch TargetGroup dimension suffix (targetgroup/name/id), filled after first sync."
  type        = string
  default     = ""
}

variable "alb_5xx_threshold" {
  description = "ALB target 5xx count per 60s that triggers the alarm."
  type        = number
  default     = 10
}

variable "rds_cpu_threshold" {
  description = "RDS CPU utilization (%) that triggers the alarm."
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold" {
  description = "RDS free storage (bytes) below which the alarm triggers. Default 5 GiB."
  type        = number
  default     = 5368709120
}

variable "node_count_threshold" {
  description = "Minimum in-service node count; alarm fires when the ASG drops below this."
  type        = number
  default     = 1
}

variable "cp_5xx_threshold" {
  description = "EKS API-server 5xx requests per 5-minute period that trigger the alarm."
  type        = number
  default     = 5
}
