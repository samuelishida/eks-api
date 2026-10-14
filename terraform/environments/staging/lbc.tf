# AWS Load Balancer Controller (LBC) — IRSA role (Inc 6).
#
# The LBC chart (apps/argocd/lbc.yaml) runs in kube-system under the service
# account `aws-load-balancer-controller`, annotated with this role's ARN. The
# trust policy is the standard IRSA pattern: federated to the cluster's OIDC
# provider, pinned to that service account by `sub` and the STS `aud`.
#
# The OIDC provider is created by the eks module, so this role lives at the
# environment level (it cannot be an input to the module without a cycle).
data "aws_caller_identity" "current" {}

locals {
  lbc_oidc_issuer = "https://${replace(module.eks.oidc_provider_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}"
}

resource "aws_iam_role" "lbc" {
  name = "eks-api-lbc-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.lbc_oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.lbc_oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "eks-api-lbc-irsa"
    Env  = var.env_name
  }
}

# AWS-managed policy with the core LBC permissions (ELB/EC2 management).
resource "aws_iam_role_policy_attachment" "lbc_aws_managed" {
  role       = aws_iam_role.lbc.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancerControllerPolicy"
}

# Official LBC inline policy (canonical, from the LBC docs): the remaining
# EC2 describe/create/modify actions, ELB tag + modify actions, and ECS
# describes that the AWS-managed policy does not cover.
resource "aws_iam_role_policy" "lbc" {
  name = "eks-api-lbc-inline"
  role = aws_iam_role.lbc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:CreateTags",
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DeleteNetworkInterfacePermission",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DeleteTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListeners",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:AddTagsToResource",
          "elasticloadbalancing:RemoveTagsFromResource",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "ecs:Describe*",
        ]
        Resource = "*"
      },
    ]
  })
}

output "lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller (paste into apps/argocd/lbc.yaml serviceAccount.annotations)."
  value       = aws_iam_role.lbc.arn
}
