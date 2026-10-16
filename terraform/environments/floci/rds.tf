# RDS — private-only PostgreSQL (floci, shape-validation only).

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
  resource_name          = var.name
  region                 = var.region
  env                    = var.env_name
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [module.network.rds_security_group_id]

  multi_az                = false
  deletion_protection     = false
  storage_type            = "gp2"
  skip_final_snapshot     = true
  backup_retention_period = 7
  performance_insights    = false
}
