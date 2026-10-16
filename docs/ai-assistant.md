# Generative-AI deliverable — how the AI built (and was corrected in) this repo

This document is the required **Generative-AI** artifact: the prompt used to
generate the IaC scaffolding, representative output, and — most importantly —
how the AI's suggestions were **validated**, **corrected**, and **assessed**.
Every correction below is a real change made during this build, not a
hypothetical list.

## (a) The prompt

**Initial brief (interview task):**

> Build a production-grade repo that deploys a containerized API to AWS EKS:
> the API must be reachable from outside the cluster/account (public ALB), the
> database must NOT be reachable from outside; allow private ingress from the managed
> workload node group. Standard VPC CNI pods on those nodes share this boundary. The DB must have persistent storage (RDS PostgreSQL)
> and the app must run with several replicas. Use Terraform, Helm, and GitOps
> (ArgoCD) following best practice, with CI/CD, monitoring, and a local
> validation path (Floci emulator) that does not require an AWS account.

**Toolchain / Floci follow-up (after the first scaffold):**

> Validate everything against the Floci AWS emulator at 127.0.0.1:4566
> (k3s-backed EKS). `make floci-validate` must: terraform apply the `floci`
> env, generate a kubeconfig for the created cluster, server-side dry-run the
> Helm chart, and client-side dry-run the ArgoCD app-of-apps manifests. No
> real AWS calls, no secrets in the repo, no `:latest` pins.

The local validation path now pairs Floci resource-shape checks with Kind API-to-PostgreSQL E2E. Floci validates Terraform and Kubernetes resource wiring; Kind builds and runs the API image, starts PostgreSQL, and verifies health, readiness, and CRUD. Neither substitutes for real-AWS validation of ALB, ECR, RDS, IAM, or VPC behavior.

## (b) Representative output

Terraform — private-only RDS with write-only password (from
`terraform/modules/rds/main.tf`, which wraps `terraform-aws-modules/rds/aws`
`~> 7.2.2`):

```hcl
resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2.2"

  identifier = "${var.resource_name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  db_name        = var.db_name
  username       = var.username
  instance_class = var.instance_class
  # v7 removed the readable `password` argument: write-only, never readable back.
  password_wo    = random_password.db.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  multi_az                         = var.multi_az
  deletion_protection              = var.deletion_protection
  skip_final_snapshot              = var.skip_final_snapshot
  final_snapshot_identifier_prefix = var.skip_final_snapshot ? null : "${var.resource_name}-final"
  backup_retention_period          = var.backup_retention_period

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids  # ingress only from workload node group SG

  # Private-only: no `publicly_accessible` argument (defaults false).
}
```

Helm — ALB Ingress via the AWS Load Balancer Controller (from
`charts/api/templates/ingress.yaml`):

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "api.labels" . | nindent 4 }}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: {{ .Values.ingress.scheme }}
    alb.ingress.kubernetes.io/target-type: ip
    {{- if .Values.ingress.tls }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
    {{- else }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    {{- end }}
    {{- if .Values.ingress.certArn }}
    alb.ingress.kubernetes.io/certificate-arn: {{ .Values.ingress.certArn }}
    {{- end }}
    {{- with .Values.ingress.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  {{- if .Values.ingress.host }}
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "api.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
  {{- end }}
{{- end }}
```

## (c) Validation → correction → assessment

### Validated (with the real toolchain)

| Check | Command | Result |
| --- | --- | --- |
| Terraform formatting | `terraform fmt -check -recursive` | pass |
| Terraform, all envs + bootstrap | `terraform validate` × 5 | pass |
| Helm chart, all env values | `helm lint` × 3 | pass |
| Chart renders | `helm template` (dev/staging/prod) | YAML parses; expected Deployment, Service, Ingress |
| Go API | `go vet ./... && go test ./...` | pass in Go container |
| API image | `docker build` | pass |
| API runtime | container with unavailable DB | `/healthz` 200, `/readyz` 503; password absent from logs |
| LBC and ArgoCD charts | Helm render at pinned versions | pass; IRSA values and health customization present |
| Floci shape validation | `make floci-validate` | Terraform apply, Helm server dry-run/install, Secret/resources, PodScheduled, Argo manifest parse; no AWS data-plane proof |
| Kind API data-path E2E | make kind-e2e | API image + PostgreSQL in isolated Kind cluster; health/readiness/CRUD/post-delete 404 passed; no AWS ingress proof |

### Corrected (real changes made during this build)

1. **`ingress-nginx` → AWS Load Balancer Controller.** The first scaffold used
   the nginx ingress controller; the `ingress-nginx` repo is archived/retiring.
   Replaced with the AWS LBC (v3.6.0), official versioned IAM policy, and IRSA
   role — the AWS-native path. Removed an unsupported pod annotation.
2. **RDS `password` → `password_wo`.** The rds module v7 removed the readable
   `password` argument in favor of the write-only `password_wo`; the AI's first
   pass used the old attribute. Fixed, and the password now flows
   `random_password` → `password_wo` → k8s Secret only.
3. **`database_name` → `db_name`** and **`final_snapshot_identifier` →
   `final_snapshot_identifier_prefix`** — rds module v7 argument renames the
   first pass got wrong.
4. **`encryption_configuration` block** — the v7 module moved encryption into a
   nested block; the flat `storage_encrypted`-style top-level args the AI
   emitted were rejected by `terraform validate`.
5. **ECR lifecycle policy as a separate resource** — the AI initially inlined
   lifecycle rules where the module expects a distinct
   `aws_ecr_repository` + policy split; split it.
6. **ACM validation is DNS-owner work** — Terraform requests staging/prod
   certificates and outputs DNS validation options. It does not create Route53
   records or wait for issuance; operators create the listed CNAME records.
7. **k8s objects via `kubernetes_namespace_v1` / `kubernetes_secret_v1`** — the
   first pass created the DB secret imperatively; replaced with declarative
   Terraform resources so state owns them.
8. **LBC IRSA uses a reusable module.** Environment roots pass the EKS OIDC
   issuer to `modules/lbc/`, which creates the role and matching inline policy.
9. **Floci: AWS provider v6 falls back to real AWS for any service not in
   `endpoints`.** The first `floci` apply leaked `iam`/`logs` calls to real AWS
   (`InvalidClientTokenId`). Fixed by enumerating every service endpoint in
   `environments/floci/main.tf`.
10. **LBC policy consistency** — replaced the nonexistent AWS-managed policy
    attachment with the versioned upstream policy JSON used by the chart.
11. **Quoted-token 401.** `aws eks get-token --output json --query 'status.token'`
    returns the token JSON-encoded (surrounding `"`), which the k8s API rejects
    with 401. Switched to `--output text` (verified: 474 chars, HTTP 200).
12. **Static-token kubeconfig.** The emulator's default kubeconfig points at a
    different demo cluster, and its exec-plugin auth lacks credentials. The
    Floci validation script writes a static-token kubeconfig for its cluster.
13. **Floci check now installs the chart.** Validation does server-side dry-run,
    Helm install, Secret/resource checks, and waits for pod scheduling; it does
    not claim AWS data-plane or API readiness.

### Assessed

- **Edge cases:** empty/missing `image.tag` fails `helm lint`; RDS
  `skip_final_snapshot` is `false` in prod (no accidental data loss on
  destroy); `TreatMissingData` set so a missing metric doesn't page.
- **Security:** private-only EKS endpoint + RDS; workload-node-SG→RDS-SG only
  (standard VPC CNI pods share node ENIs); non-root
  distroless image (uid 65532); IRSA everywhere (no node IAM for workloads);
  OIDC CI (no long-lived keys); KMS least-privilege (specific roles, no
  `kms:*` on `*`); S3 state bucket versioned + KMS + public-access-blocked.
- **Compliance:** no secrets in the repo (`.gitignore` covers `.env`,
  `*.tfstate`, `floci.auto.tfvars`); `CODEOWNERS` gates staging/prod value
  changes; `provenance-gate.yml` blocks force-pushes to `main`.
- **Performance:** one shared NAT (cost) vs per-AZ (resilience) is an explicit
  `one_nat_gateway_per_az` knob; ASG min/max/desired per env; ip-targeting ALB
  (no node-port overhead).
- **Cost:** Floci path is free; per-env sizing in tfvars (dev `t3.small` ×1);
  RDS storage/CPU alarms catch runaway growth; ECR lifecycle expires old
  images.
- **Idiomatic:** pinned providers/modules (`versions.tf`), `password_wo`,
  app-of-apps GitOps, `workflow_run`-gated deploy PR, merge-commit provenance
  gate, `TreatMissingData`, `PAY_PER_REQUEST` lock table with PITR.
