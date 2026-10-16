variable "name" {
  description = "Unique resource name including environment."
  type        = string
}

variable "policy_name" {
  description = "Inline IAM policy name, stable across state moves."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN for the IRSA trust policy."
  type        = string
}
