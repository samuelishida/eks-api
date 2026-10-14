terraform {
  backend "s3" {
    bucket         = var.backend_bucket
    key            = "dev/terraform.tfstate"
    region         = var.region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}
