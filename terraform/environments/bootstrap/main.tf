# One-off bootstrap root: creates the S3 state bucket + DynamoDB lock table
# that every per-env `terraform init` (dev/staging/prod) needs as its remote
# backend. Run it ONCE, then `terraform destroy` it only when tearing down the
# whole project (destroying it while envs still point at it breaks their init).
#
#   terraform -chdir=terraform/environments/bootstrap init
#   terraform -chdir=terraform/environments/bootstrap apply -auto-approve
#
# Bucket names are globally unique: substitute <account-id> into the bucket
# name (and the matching `backend_bucket` in each env's tfvars) before apply.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for the state backend"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform state (globally unique — include your account ID)"
  type        = string
  default     = "eks-api-tfstate-000000000000"
}

variable "lock_table" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "eks-api-tflock"
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket

  tags = {
    Name = var.state_bucket
    Use  = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.lock_table
    Use  = "terraform-state-lock"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.lock.name
}
