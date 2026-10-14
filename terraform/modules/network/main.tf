# Network module — RDS security group, pod-SG ALB rule, VPC endpoints, prod ACM cert.
#
# Providers are configured at the environment root, never here.
#
# Ownership split (avoids double-creation):
# - The EKS module OWNS the EKS VPC interface endpoint (it needs the cluster ARN).
# - This module OWNS the ECR interface endpoint + the S3 gateway endpoint.
#
# Security model:
# - RDS SG: ingress 5432 ONLY from the EKS pod security group (where the API pods run).
# - Pod SG: an ingress rule for 8080 from the VPC CIDR so the ALB (ip-targeting) can reach
#   the pods. The ALB's own SG is created at runtime by the AWS Load Balancer Controller
#   (not by Terraform), so its SG id is not knowable at apply time — the VPC CIDR is the
#   accepted broadening.

# RDS security group: only the pod SG may reach Postgres.
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS ${var.name}: ingress 5432 only from the EKS pod SG"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from EKS pods only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.pod_security_group_id]
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

# Pod-SG ingress rule for ALB ip-targeting (8080 from the VPC CIDR).
resource "aws_vpc_security_group_ingress_rule" "pod_alb" {
  security_group_id = var.pod_security_group_id
  description       = "ALB -> API pods (ip-targeting); ALB SG is runtime-created, so VPC CIDR is used"
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

resource "aws_acm_certificate_validation" "alb" {
  count = var.create_acm_cert ? 1 : 0

  certificate_arn = aws_acm_certificate.alb[0].arn
}
