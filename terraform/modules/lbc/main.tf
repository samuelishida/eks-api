data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_issuer = replace(
    var.oidc_provider_arn,
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/",
    "",
  )
}

resource "aws_iam_role" "this" {
  name = "${var.name}-lbc-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.name}-lbc-irsa"
    Env  = var.env
  }
}

resource "aws_iam_role_policy" "this" {
  name   = var.policy_name
  role   = aws_iam_role.this.id
  policy = file("${path.module}/../../policies/aws-load-balancer-controller-v3.6.0.json")
}
