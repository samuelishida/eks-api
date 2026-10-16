# RDS — private-only PostgreSQL (staging).

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-${var.env_name}-db"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.name}-${var.env_name}-db"
    Env  = var.env_name
  }
}

module "rds" {
  source = "../../modules/rds"

  name                   = var.name
  resource_name          = "${var.name}-${var.env_name}"
  region                 = var.region
  env                    = var.env_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [module.network.rds_security_group_id]

  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 7
  performance_insights    = false
}
