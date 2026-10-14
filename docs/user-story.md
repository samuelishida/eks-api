# Epic — Repeatable, Secure, Multi-Environment EKS Deployment

> **As a** platform engineer,
> **I want** a repeatable, secure, cost-effective, multi-environment deployment of a containerized
> API on AWS EKS,
> **so that** I (and any reviewer) can stand up the stack in any environment from a single git repo,
> with the API publicly reachable and the database private, without hand-cutting YAML or Terraform.

## Goals

- The **API** is reachable from outside (ALB). The **database** is **not** reachable from outside —
  only the API talks to it, over the private network.
- The **DB** has persistent storage (RDS) and the app runs with **several replicas**.
- **EKS** orchestrates; everything is **Terraform** (IaC) + **Helm** (packaging) + **GitOps** (ArgoCD).
- The repo is the **single source of truth**; promotion is auditable (PR-gated).

## Task breakdown (mirrors the plan's increments)

### E1 — Repo scaffold + this epic
Create the repo tree, `README`, `Makefile`, `.gitignore`, `.editorconfig`, and this epic.
- **Acceptance:** `git status` shows a clean, sensible tree; `make help` lists targets; this file reads
  as a self-contained epic.

### E2 — Terraform: VPC + EKS (per environment)
Shared `modules/` (vpc, eks) + per-env roots (`dev`, `staging`, `prod`, `floci`) with real
S3+DynamoDB backends and pinned providers/modules. Private-only EKS endpoint access; managed node
group with **both** `AmazonEKSWorkerNodePolicy` and `AmazonEKS_CNI_Policy`; a dedicated pod security
group.
- **Acceptance:** `terraform plan` for `dev` + `floci` succeeds with a coherent VPC+EKS graph; no
  provider block inside any child module; no fake account/bucket placeholders.

### E3 — Terraform: RDS + network + ECR
Private-only RDS PostgreSQL (write-only `password_wo`, least-privilege KMS key, SG reachable **only
from the pod SG**); network module (RDS SG, pod-SG rule for ALB ip-targeting, VPC endpoints, prod ACM
cert); ECR repo with scan-on-push + lifecycle. The DB password flows into a `kubernetes_secret`.
- **Acceptance:** `terraform plan` shows RDS in private subnets with the SG rule sourced from the pod
  SG; `rg "publicly_accessible|public_subnet" terraform/` returns nothing for RDS.

### E4 — Sample API + Dockerfiles
A small Go API (chi + pgx) with `/healthz`, `/readyz` (DB-backed), and a minimal CRUD; idempotent
schema bootstrap. Multi-stage **distroless non-root** Dockerfile. A second **Node** sample Dockerfile
(reference only).
- **Acceptance:** `go vet ./... && go test ./...` green; `docker build` produces a small non-root
  image; `/readyz` fails (503) when the DB is unreachable.

### E5 — Helm chart for the API
Custom chart `charts/api/` (Deployment, Service, ALB Ingress with ip-targeting annotation, probes,
resources, non-root securityContext, existing-secret reference). Per-env `values-<env>.yaml`.
- **Acceptance:** `helm lint` + `helm template` (per env) render a Deployment, Service, ALB Ingress, and
  Secret reference with correct probes/resources/replicas.

### E6 — GitOps: ArgoCD app-of-apps (+ LBC + namespaces)
ArgoCD v3.5.5 installed in-cluster; an app-of-apps layout where each env is an `Application` pointing
at `charts/api/` with env value files; the **AWS Load Balancer Controller** Application is installed
**before** the api Applications (its IRSA role is created in Terraform).
- **Acceptance:** `kubectl apply --dry-run=client -f apps/argocd/` accepts the Project + Applications;
  LBC is a dependency of the api apps, not a sibling.

### E7 — CI/CD: GitHub Actions
Build/test/push to ECR via **OIDC** (tag = git SHA); a **PR-gated** deploy workflow that opens a PR
bumping `image.tag` (dev auto-promoted; staging/prod via reviewed PRs); a `terraform` workflow
(`init -backend=false` + `validate` + `fmt -check`); a **push-provenance gate** (refuse main commits
without a merged PR).
- **Acceptance:** `actionlint` clean; workflows reference OIDC (`id-token: write`) and the correct
  `workflow_run`/`head_branch` conditions; the tag PR is idempotent.

### E8 — Monitoring + alerts
CloudWatch control-plane + node logging; ECR scan-on-push; CloudWatch alarms (ALB 5xx / target-group
health, RDS CPU / free storage, node count) fanned out to an **SNS** topic; Prometheus/Grafana
documented as an optional add-on.
- **Acceptance:** `terraform plan` shows the SNS topic + alarms with correct metric sources and env
  thresholds.

### E9 — Local validation (Floci)
Validate the whole stack against the Floci emulator: `terraform apply` (floci) converges, chart +
ArgoCD manifests apply to k3s, and the API Deployment / `api-db-credentials` Secret / Ingress are
created with ALB annotations. **Shape** validation only (ECR/RDS have no data plane in Floci).
- **Acceptance:** `make floci-validate` green; the API pod is **Scheduled** (not-ready expected); the
  Ingress carries the ALB annotations.

### E10 — Docs: runbook + AI deliverable
`docs/runbook-aws.md` (real-AWS apply, state bootstrap first), `docs/ai-assistant.md` (the
Generative-AI deliverable: prompt, output, validation/correction/assessment), `docs/architecture.md`
(diagram + decisions).
- **Acceptance:** a reviewer can follow the runbook top-to-bottom; the AI deliverable is complete and
  consistent with the validated repo.

## Non-goals (out of scope)

- Live AWS apply in this exercise (the real-account path is a ready-to-run runbook).
- Floci as a performance/billing proxy.
- A production migration tool (the sample uses an idempotent bootstrap instead).
