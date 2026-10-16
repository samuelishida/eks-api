variable "name" {
  description = "Base name for the RDS instance and KMS key."
  type        = string
}

variable "resource_name" {
  description = "Globally unique name for AWS resources, including environment."
  type        = string
}

variable "region" {
  description = "AWS region, used to scope KMS grant use to RDS in this region."
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

# The registry RDS module requires `instance_class` (default null is invalid).
# `db.t3.micro` is the smallest general-purpose class — fine for dev/floci;
# prod should override with a larger class.
variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
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

variable "storage_type" {
  description = "RDS storage type. Real environments use gp3; Floci keeps gp2 because it cannot apply storage type changes."
  type        = string
  default     = "gp3"
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

# The registry RDS module defaults `create_db_parameter_group = true` with
# `family = null`, which fails (the `aws_db_parameter_group` resource requires
# `family`). This wrapper never manages parameter groups, so default to not
# creating one (the instance uses the engine default parameter group). An env
# that wants a custom parameter group can set this true AND pass `family`.
variable "create_db_parameter_group" {
  description = "Create a DB parameter group (requires `family` to be set)."
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
