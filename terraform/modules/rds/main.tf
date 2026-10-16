# RDS module — wraps terraform-aws-modules/rds/aws 7.2.2.
#
# Providers are configured at the environment root, never here.
#
# Design notes:
# - Private-only: the DB subnet group uses private subnets; `publicly_accessible`
#   is never set (defaults false). The RDS SG (created in the network module)
#   allows ingress 5432 only from the managed workload node group security group.
# - v7.0.0+ removed the `password` argument: use the write-only `password_wo`
#   (fed by a `random_password` resource). TF cannot read `password_wo` back, so
#   the same `random_password.result` flows into both the RDS module and the K8s
#   secret at the env root (single source of truth).
# - A customer-managed KMS key is scoped to RDS use; only the Terraform caller
#   may create grants, and only for RDS requests in this region.

resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  keepers = {
    name = var.name
  }
}

resource "aws_kms_key" "rds" {
  description             = "RDS storage encryption key for ${var.resource_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAdmin"
        Effect = "Allow"
        Principal = {
          # KMS key policies cannot name an STS assumed-role session ARN.
          # Delegate within the account; the caller still needs IAM permission.
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:PutKeyPolicy",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:UpdateKeyDescription",
          "kms:EnableKeyRotation",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowRDSGrant"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:CreateGrant"
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
          StringEquals = {
            "kms:ViaService" = "rds.${var.region}.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${var.resource_name}-rds"
    Env  = var.env
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.resource_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2.2"

  identifier = "${var.resource_name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  db_name        = var.db_name
  username       = var.username
  instance_class = var.instance_class
  password_wo    = random_password.db.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  multi_az                         = var.multi_az
  deletion_protection              = var.deletion_protection
  skip_final_snapshot              = var.skip_final_snapshot
  final_snapshot_identifier_prefix = var.skip_final_snapshot ? null : "${var.resource_name}-final"
  backup_retention_period          = var.backup_retention_period

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids

  # Private-only: no `publicly_accessible` argument (defaults false).

  performance_insights_enabled          = var.performance_insights
  performance_insights_kms_key_id       = var.performance_insights ? aws_kms_key.rds.arn : null
  performance_insights_retention_period = var.performance_insights ? 7 : null

  # The wrapper does not manage parameter groups; the registry module's default
  # (create=true, family=null) is invalid. Opt out by default.
  create_db_parameter_group = var.create_db_parameter_group

  tags = {
    Name = var.resource_name
    Env  = var.env
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
