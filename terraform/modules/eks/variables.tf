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

# Concrete `<major>.<minor>` pinned for the managed node group. When set, the
# registry module skips the `aws_eks_cluster_versions` data source (its count is
# `var.create && var.kubernetes_version == null`), which cannot be evaluated at
# plan time (it depends on the cluster, not known until apply). Default `1.33`
# is a supported EKS version and matches the k3s cluster Floci creates.
variable "kubernetes_version" {
  description = "Kubernetes <major>.<minor> pinned for the managed node group (avoids the apply-time cluster-versions data source)."
  type        = string
  default     = "1.33"
}

# When true, the registry node-group module resolves the optimized AMI via an
# SSM `GetParameter` call. Floci does not serve that SSM path, so the floci env
# sets this to false (node group then uses the default AL2023 AMI type with no
# release-version lookup). Real envs keep the default (true) — no behavior change.
variable "use_latest_ami_release_version" {
  description = "Resolve the optimized node-group AMI via SSM (disable for Floci, which does not serve that SSM parameter)."
  type        = bool
  default     = true
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
