# Network module — RDS security group, workload-node ingress rule, VPC endpoints, ACM cert.
#
# Providers are configured at the environment root, never here.
#
# Ownership split (avoids double-creation):
# - The EKS module OWNS the EKS VPC interface endpoint (it needs the cluster ARN).
# - This module OWNS the ECR interface endpoint + the S3 gateway endpoint.
#
# Security model:
# - RDS SG: ingress 5432 only from the dedicated workload node-group SG. Standard
#   VPC CNI pods share node ENIs; this does not isolate traffic to one Kubernetes pod.
# - Workload node SG: permits 8080 from the VPC so ALB IP targets can be reached.

# RDS security group: only workload nodes may reach Postgres.
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS ${var.name}: ingress 5432 only from workload node group"
  vpc_id      = var.vpc_id

  # Preserve existing SG state: AWS security-group descriptions are immutable.
  # New environments use the accurate workload-node description above.
  lifecycle {
    ignore_changes = [description]
  }

  ingress {
    description     = "Postgres from workload nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.workload_node_security_group_id]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds"
    Env  = var.env
  }
}

# Workload node SG ingress rule for ALB IP targets (8080 from the VPC CIDR).
resource "aws_vpc_security_group_ingress_rule" "pod_alb" {
  security_group_id = var.workload_node_security_group_id
  description       = var.alb_ingress_rule_description
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = {
    Name = "${var.name}-pod-alb"
    Env  = var.env
  }
}

# ECR interface endpoint (this module owns it; the EKS module owns the EKS endpoint).
resource "aws_vpc_endpoint" "ecr_docker" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  subnet_ids          = var.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name}-ecr-dkr"
    Env  = var.env
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type = "Interface"

  subnet_ids          = var.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name}-ecr-api"
    Env  = var.env
  }
}

# S3 gateway endpoint (cheap, no ENI).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = {
    Name = "${var.name}-s3"
    Env  = var.env
  }
}

# Security group for the interface endpoints.
resource "aws_security_group" "vpce" {
  name        = "${var.name}-vpce"
  description = "VPC interface endpoints (ECR) for ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-vpce"
    Env  = var.env
  }
}

# Prod-only ACM certificate for the ALB TLS (request + DNS validation record).
# The ARN is exported to the chart values (ingress.certArn).
resource "aws_acm_certificate" "alb" {
  count = var.create_acm_cert ? 1 : 0

  domain_name       = var.acm_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name}-alb"
    Env  = var.env
  }
}
