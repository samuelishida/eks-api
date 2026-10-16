variable "name" {
  description = "Base name for the VPC (VPC name is <name>-<env>)."
  type        = string
}

variable "env" {
  description = "Environment name used in naming and tags."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block for this environment (e.g. 10.10.0.0/16)."
  type        = string
}

variable "azs" {
  description = "Availability zones to place public/private subnets in."
  type        = list(string)
}

variable "per_az_nat" {
  description = "Create one NAT gateway per AZ (prod) instead of a single shared NAT gateway."
  type        = bool
  default     = false
}

variable "manage_default_network_acl" {
  description = "Whether to manage the VPC default network ACL; disable for Floci because it does not round-trip IPv6 rules consistently."
  type        = bool
  default     = true
}
