output "endpoint" {
  description = "RDS endpoint (hostname:port)."
  value       = module.rds.db_instance_endpoint
}

output "address" {
  description = "RDS hostname."
  value       = module.rds.db_instance_address
}

output "port" {
  description = "RDS port."
  value       = module.rds.db_instance_port
}

output "db_name" {
  description = "Database name."
  value       = var.db_name
}

output "username" {
  description = "Master username."
  value       = var.username
}

output "password" {
  description = "Generated master password (from random_password; flows into the K8s secret at the env root)."
  value       = random_password.db.result
  sensitive   = true
}

output "kms_key_id" {
  description = "KMS key ID used for storage encryption."
  value       = aws_kms_key.rds.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN."
  value       = aws_kms_key.rds.arn
}
