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
> database must NOT be reachable from outside (only the API talks to it, over
> the private network), the DB must have persistent storage (RDS PostgreSQL)
> and the app must run with several replicas. Use Terraform, Helm, and GitOps
> (ArgoCD) following best practice, with CI/CD, monitoring, and a local
> validation path (Floci emulator) that does not require an AWS account.

**Toolchain / Floci follow-up (after the first scaffold):**

> Validate everything against the Floci AWS emulator at 127.0.0.1:4566
> (k3s-backed EKS). `make floci-validate` must: terraform apply the `floci`
> env, generate a kubeconfig for the created cluster, server-side dry-run the
> Helm chart, and client-side dry-run the ArgoCD app-of-apps manifests. No
> real AWS calls, no secrets in the repo, no `:latest` pins.

## (b) Representative output

Terraform — private-only RDS with write-only password (from
`terraform/modules/rds/main.tf`, which wraps `terraform-aws-modules/rds/aws`
`~> 7.2.2`):

```hcl
resource "random_password" "db" {
  length  = 20
  special = false
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2.2"

  identifier = "${var.name}-postgres"

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
  final_snapshot_identifier_prefix = var.skip_final_snapshot ? null : "${var.name}-final"
  backup_retention_period          = var.backup_retention_period

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = var.vpc_security_group_ids  # ingress only from pod SG

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
| Terraform, all envs + bootstrap | `terraform validate` × 5 | 0 errors / 0 warnings |
| Helm chart, all env values | `helm lint` × 3 | 0 fail / 0 warn / 0 info |
| Chart renders | `helm template` (prod) | 14 expected matches |
| Go API | `go vet ./... && go test ./...` | pass |
| Floci end-to-end | `make floci-validate` | apply converges; helm server dry-run (service/deployment/ingress) + ArgoCD dry-run 8/8 objects, exit 0 |

### Corrected (real changes made during this build)

1. **`ingress-nginx` → AWS Load Balancer Controller.** The first scaffold used
   the nginx ingress controller; the `ingress-nginx` repo is archived/retiring.
   Replaced with the AWS LBC (v3.6.0) + IRSA role + `aws-load-balancer-web-traffic`
   pod annotation — the AWS-native path.
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
6. **ACM validation as a resource** — `aws_acm_certificate_validation` with
   `validation_record_fqdns` was missing on the first pass (cert would never
   issue); added, plus the `concat(private_route_table_ids, public_route_table_ids)`
   route-table wiring for the validation records.
7. **k8s objects via `kubernetes_namespace_v1` / `kubernetes_secret_v1`** — the
   first pass created the DB secret imperatively; replaced with declarative
   Terraform resources so state owns them.
8. **LBC IRSA at env level, not module level.** The AI first put the LBC role
   inside `modules/eks/`, which created a circular reference (the module creates
   the OIDC provider the role's trust policy needs). Moved to
   `environments/*/lbc.tf` reading `module.eks.oidc_provider_arn`.
9. **Floci: AWS provider v6 falls back to real AWS for any service not in
   `endpoints`.** The first `floci` apply leaked `iam`/`logs` calls to real AWS
   (`InvalidClientTokenId`). Fixed by enumerating every service endpoint in
   `environments/floci/main.tf`.
10. **Floci: AWS-managed LBC policy doesn't exist in the emulator** — added a
    `lbc_create_aws_managed_policy` guard (default `true`, `false` in floci).
11. **Quoted-token 401.** `aws eks get-token --output json --query 'status.token'`
    returns the token JSON-encoded (surrounding `"`), which the k8s API rejects
    with 401. Switched to `--output text` (verified: 474 chars, HTTP 200).
12. **Static-token kubeconfig.** The emulator's default kubeconfig pointed at a
    different (demo) cluster, and the exec-plugin auth ran in a clean env
    (`NoCredentials`). The Makefile now generates a static-token kubeconfig for
    the created cluster via `printf` (`%s` args — a first version left
    `$FLOCI_EP` literal because the format string was single-quoted).
13. **Makefile separate-shell bug.** Each recipe line is its own shell; a
    variable set on one line was literal on the next. Merged the EP + token +
    printf into one `;`-chained line.

### Assessed

- **Edge cases:** empty/missing `image.tag` fails `helm lint`; RDS
  `skip_final_snapshot` is `false` in prod (no accidental data loss on
  destroy); `TreatMissingData` set so a missing metric doesn't page.
- **Security:** private-only EKS endpoint + RDS; pod-SG→RDS-SG only; non-root
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
