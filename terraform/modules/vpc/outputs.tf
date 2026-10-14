output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public subnet IDs (one per AZ)."
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private subnet IDs (one per AZ) — EKS nodes and RDS live here."
  value       = module.vpc.private_subnets
}

output "route_table_ids" {
  description = "All VPC route table IDs (for the S3 gateway endpoint)."
  value       = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
}
