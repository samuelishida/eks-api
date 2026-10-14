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

output "rds_endpoint" {
  description = "RDS endpoint (private)."
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "RDS address (private)."
  value       = module.rds.address
}

output "rds_port" {
  description = "RDS port."
  value       = module.rds.port
}

output "rds_db_name" {
  description = "RDS database name."
  value       = module.rds.db_name
}

output "rds_username" {
  description = "RDS master username."
  value       = module.rds.username
}

output "ecr_repository_url" {
  description = "ECR repository URL for the API image."
  value       = module.ecr.repository_url
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (empty when not created)."
  value       = module.network.acm_certificate_arn
}

output "db_secret_name" {
  description = "Name of the DB credentials Secret in the cluster."
  value       = kubernetes_secret_v1.api_db_credentials.metadata[0].name
}

output "api_namespace" {
  description = "Kubernetes namespace for the API."
  value       = kubernetes_namespace_v1.api.metadata[0].name
}
