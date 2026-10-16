variable "region" {
  description = "AWS region."
  type        = string
}

variable "name" {
  description = "Base name for resources in this environment."
  type        = string
  default     = "eks-api"
}

variable "env_name" {
  description = "Environment name (dev/staging/prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for this environment."
  type        = string
}

variable "azs" {
  description = "Availability zones for subnets."
  type        = list(string)
}

variable "per_az_nat" {
  description = "One NAT gateway per AZ (prod) instead of a single shared one."
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "Instance types for the EKS managed node group."
  type        = list(string)
}

variable "asg_min" {
  description = "ASG minimum size for the node group."
  type        = number
}

variable "asg_max" {
  description = "ASG maximum size for the node group."
  type        = number
}

variable "asg_desired" {
  description = "ASG desired size for the node group."
  type        = number
}

variable "cluster_log_types" {
  description = "EKS control-plane log types to enable."
  type        = map(string)
  default = {
    api               = "true"
    audit             = "true"
    auth              = "true"
    controllerManager = "true"
    scheduler         = "true"
  }
}

variable "alert_email" {
  description = "Optional SNS email recipient for CloudWatch alarms. Confirm the subscription after apply."
  type        = string
  default     = ""
}

variable "acm_domain" {
  description = "ACM-validated domain for the prod ALB TLS certificate."
  type        = string
  default     = "api.example.com"
}
