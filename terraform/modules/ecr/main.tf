# ECR module — repository with scan-on-push, encryption, and a lifecycle rule.
#
# Providers are configured at the environment root, never here.

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.name
    Env  = var.env
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [
      {
        priority = 1
        selection = {
          selection_criteria = {
            tagStatus = "ANY"
          }
          selection_count_type = "imageCountMoreThan"
          count_number         = var.keep_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
