variable "name" {
  description = "Base name for the cluster (cluster name is <name>-<env>)."
  type        = string
}

variable "env" {
  description = "Environment name used in naming and tags."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the cluster lives in."
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs for the cluster and the managed node group."
  type        = list(string)
}

variable "node_instance_types" {
  description = "Instance types for the managed node group (e.g. [\"t3.small\"])."
  type        = list(string)
}

variable "asg_min" {
  description = "ASG minimum size for the managed node group."
  type        = number
}

variable "asg_max" {
  description = "ASG maximum size for the managed node group."
  type        = number
}

variable "asg_desired" {
  description = "ASG desired size for the managed node group."
  type        = number
}

variable "logging" {
  description = "Cluster control-plane log types to enable (e.g. { api = true, audit = true })."
  type        = map(string)
  default     = {}
}
