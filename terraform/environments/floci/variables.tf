variable "region" {
  description = "AWS region (emulated)."
  type        = string
}

variable "floci_access_key" {
  description = "Access key for the Floci EKS auth webhook (real IAM keys; `test`/`test` is rejected). See floci.auto.tfvars.example."
  type        = string
  sensitive   = true
}

variable "floci_secret_key" {
  description = "Secret key for the Floci EKS auth webhook (real IAM keys; `test`/`test` is rejected). See floci.auto.tfvars.example."
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Base name for resources in this environment."
  type        = string
  default     = "eks-api"
}

variable "env_name" {
  description = "Environment name."
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
  default     = {}
}

variable "floci_k8s_token" {
  description = "Static bearer token for the kubernetes provider (from the Floci kubeconfig)."
  type        = string
  default     = "floci"
}
