variable "name" {
  description = "Base name for the RDS instance and KMS key."
  type        = string
}

variable "env" {
  description = "Environment name (dev/staging/prod/floci)."
  type        = string
}

variable "engine_version" {
  description = "Postgres engine version."
  type        = string
  default     = "16.4"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "app"
}

variable "username" {
  description = "Master username."
  type        = string
  default     = "app"
}

variable "allocated_storage" {
  description = "Initial allocated storage (GiB)."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Max auto-scaling storage (GiB). 0 disables autoscaling."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Enable Multi-AZ (prod)."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection (prod)."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (dev true, prod false)."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Automated backup retention (days)."
  type        = number
  default     = 7
}

variable "performance_insights" {
  description = "Enable Performance Insights (prod)."
  type        = bool
  default     = false
}

variable "db_subnet_group_name" {
  description = "DB subnet group name (must reference private subnets)."
  type        = string
}

variable "vpc_security_group_ids" {
  description = "Security group IDs for the RDS instance (the RDS SG from the network module)."
  type        = list(string)
}

variable "node_iam_role_arn" {
  description = "EKS node IAM role ARN (allowed to use the KMS key)."
  type        = string
}
