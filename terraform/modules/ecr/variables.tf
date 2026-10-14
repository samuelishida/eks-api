variable "name" {
  description = "ECR repository name."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE (default) or MUTABLE."
  type        = string
  default     = "IMMUTABLE"
}

variable "keep_image_count" {
  description = "Keep at most this many images (lifecycle rule)."
  type        = number
  default     = 30
}
