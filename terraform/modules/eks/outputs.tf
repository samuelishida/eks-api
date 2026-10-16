output "cluster_name" {
  description = "Cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Cluster API endpoint (private)."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_cert" {
  description = "Cluster CA certificate (base64-decoded)."
  value       = module.eks.cluster_certificate_authority_data
}

output "node_security_group_id" {
  description = "Cluster (node) security group ID."
  value       = module.eks.cluster_security_group_id
}

output "workload_node_security_group_id" {
  description = "Additional security group attached to the managed workload node group."
  value       = aws_security_group.pod.id
}

output "pod_security_group_id" {
  description = "Deprecated alias; this SG is attached to workload nodes, not isolated to individual pods."
  value       = aws_security_group.pod.id
}

output "oidc_provider_arn" {
  description = "Cluster OIDC provider ARN (for IRSA / workload IAM)."
  value       = module.eks.oidc_provider_arn
}

output "node_iam_role_arn" {
  description = "Managed node group IAM role ARN (needed for the KMS policy in later increments)."
  value       = module.eks.eks_managed_node_groups["node"].iam_role_arn
}

output "asg_names" {
  description = "Auto Scaling group names of the managed node groups (index by group key, e.g. [\"node\"])."
  value       = module.eks.eks_managed_node_groups
}
