# DB credentials Secret — TF is the secret owner (floci, shape-validation only).
# Keys match charts/api's db.secretKeys.

resource "kubernetes_namespace_v1" "api" {
  metadata {
    name = "api-${var.env_name}"
  }
}

resource "kubernetes_secret_v1" "api_db_credentials" {
  metadata {
    name      = "api-db-credentials"
    namespace = kubernetes_namespace_v1.api.metadata[0].name
  }

  data = {
    host     = module.rds.address
    port     = tostring(module.rds.port)
    user     = module.rds.username
    password = module.rds.password
    name     = module.rds.db_name
  }

  type = "Opaque"
}
