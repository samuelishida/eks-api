# DB credentials Secret — TF is the secret owner. The password flows from the
# random_password in the rds module into both the RDS instance (password_wo) and
# this Secret (single source of truth). Keys match charts/api's db.secretKeys.
#
# TF also creates the namespace so the Secret can be written during apply; ArgoCD's
# createNamespace (Inc 6) is then a no-op.

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
