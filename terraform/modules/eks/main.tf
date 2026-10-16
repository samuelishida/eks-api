# EKS module — wraps terraform-aws-modules/eks/aws.
#
# Providers are configured at the environment root, never here.
#
# Design notes:
# - Cluster endpoint is private-only (public access disabled). The module
#   creates the VPC interface endpoints itself — do NOT create them here.
# - Managed node group lives in the private subnets; the module attaches both
#   AmazonEKSWorkerNodePolicy and AmazonEKS_CNI_Policy to its IAM role
#   automatically.
# - A dedicated security group is attached to the managed node group. Standard
#   VPC CNI pods use node ENIs and therefore share this node-group network
#   boundary; this is not EKS Security Groups for Pods isolation.

locals {
  name = "${var.name}-${var.env}"
}

# Dedicated workload node-group security group: intra-group traffic + egress.
resource "aws_security_group" "pod" {
  name        = "${local.name}-pod"
  description = "Dedicated workload node-group security group for ${local.name}"
  vpc_id      = var.vpc_id

  # Existing Floci state used an earlier pod-oriented description. The API
  # cannot update SG descriptions in place; avoid replacing a live SG just to
  # correct this label. New environments get the accurate description above.
  lifecycle {
    ignore_changes = [description]
  }

  ingress {
    description = "Pod-to-pod traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-pod"
    Env  = var.env
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29.0"

  name = local.name

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  # Private-only cluster endpoint.
  endpoint_public_access  = false
  endpoint_private_access = true

  enabled_log_types = [for k, v in var.logging : k if v]

  eks_managed_node_groups = {
    node = {
      instance_types = var.node_instance_types
      min_size       = var.asg_min
      max_size       = var.asg_max
      desired_size   = var.asg_desired

      # Pin the node-group k8s version so the registry module does NOT create
      # the `aws_eks_cluster_versions` data source (its count depends on the
      # cluster and cannot be resolved at plan time).
      kubernetes_version = var.kubernetes_version

      # Floci does not serve the optimized-AMI SSM parameter; disable the SSM
      # lookup there (real envs keep the default true).
      use_latest_ami_release_version = var.use_latest_ami_release_version

      # Nodes in the private subnets only (no public IP on nodes).
      subnet_ids = var.private_subnets

      # Stable name derived from the cluster name (never from an SSH key).
      iam_role_name = "${local.name}-node-role"

      # The module attaches AmazonEKSWorkerNodePolicy + AmazonEKS_CNI_Policy
      # to this role automatically for managed node groups.

      # Attach this additional SG to the dedicated managed node group.
      vpc_security_group_ids = [aws_security_group.pod.id]
    }
  }

  tags = {
    Name = local.name
    Env  = var.env
  }
}
