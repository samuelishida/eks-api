# RDS — private-only PostgreSQL (staging).

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.name}-db"
    Env  = var.env_name
  }
}

module "rds" {
  source = "../../modules/rds"

  name                   = var.name
  env                    = var.env_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [module.network.rds_security_group_id]
  node_iam_role_arn      = module.eks.node_iam_role_arn

  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 7
  performance_insights    = false
}
