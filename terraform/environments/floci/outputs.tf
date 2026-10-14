output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint (private)."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_cert" {
  description = "EKS cluster CA certificate (base64-decoded)."
  value       = module.eks.cluster_ca_cert
}

output "node_security_group_id" {
  description = "Cluster (node) security group ID."
  value       = module.eks.node_security_group_id
}

output "pod_security_group_id" {
  description = "Dedicated pod security group ID."
  value       = module.eks.pod_security_group_id
}

output "oidc_provider_arn" {
  description = "Cluster OIDC provider ARN."
  value       = module.eks.oidc_provider_arn
}

output "node_iam_role_arn" {
  description = "Managed node group IAM role ARN."
  value       = module.eks.node_iam_role_arn
}
