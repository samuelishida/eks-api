variable "name" {
  description = "Base name for network resources."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "AWS region (for VPC endpoint service names)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (source for the workload-node ALB target rule)."
  type        = string
}

variable "workload_node_security_group_id" {
  description = "Additional SG attached to EKS managed workload nodes (RDS source + ALB target rule)."
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs (for interface endpoints)."
  type        = list(string)
}

variable "route_table_ids" {
  description = "Route table IDs (for the S3 gateway endpoint)."
  type        = list(string)
}

variable "create_acm_cert" {
  description = "Create the ACM certificate for the ALB (prod only)."
  type        = bool
  default     = false
}

variable "acm_domain" {
  description = "Domain for the ACM certificate (prod)."
  type        = string
  default     = ""
}

variable "alb_ingress_rule_description" {
  description = "Description for the ALB-to-workload ingress security group rule."
  type        = string
  default     = "ALB -> workload node IP targets; VPC CIDR used because ALB SG is runtime-created"
}
