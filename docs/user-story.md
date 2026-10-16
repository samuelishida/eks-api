# Epic — Repeatable, Secure, Multi-Environment EKS Deployment

> **As a** platform engineer,
> **I want** a repeatable, secure, cost-effective, multi-environment deployment of a containerized
> API on AWS EKS,
> **so that** I (and any reviewer) can stand up the stack in any environment from a single git repo,
> with the API publicly reachable and the database private, without hand-cutting YAML or Terraform.

## Goals

- The **API** is reachable from outside (ALB). The **database** is **not** reachable from outside —
  accessible only through the private network from the managed workload node group. Standard VPC
  CNI pods on those nodes share that network boundary.
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
group with **both** `AmazonEKSWorkerNodePolicy` and `AmazonEKS_CNI_Policy`; a dedicated security
group attached to workload nodes (standard VPC CNI pods share node network identity).
- **Acceptance:** `terraform plan` for `dev` + `floci` succeeds with a coherent VPC+EKS graph; no
  provider block inside any child module; no fake account/bucket placeholders.

### E3 — Terraform: RDS + network + ECR
Private-only RDS PostgreSQL (write-only `password_wo`, KMS key with RDS-scoped grants, SG reachable
from the workload node group); network module (RDS SG, workload-node rule for ALB IP targeting,
VPC endpoints, staging/prod ACM cert); ECR repo with scan-on-push + lifecycle. The DB password flows
into a `kubernetes_secret`.
- **Acceptance:** `terraform plan` shows RDS in private subnets with SG ingress sourced from the
  workload node group; `rg "publicly_accessible|public_subnet" terraform/` returns nothing for RDS.

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
ArgoCD v3.5.5 installed in-cluster; one environment-scoped app-of-apps root per cluster reconciles
the AppProject, AWS Load Balancer Controller Application, and API Application. Sync waves and child
Application health checks order LBC before API; Terraform creates the LBC IRSA role.
- **Acceptance:** YAML parses; the matching root applies per cluster; project, LBC, and API sync in
  wave order. Floci parses these manifests without ArgoCD CRDs.

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

### E9 — Local validation (Floci + Kind)
Floci validates Terraform/AWS resource shape, Helm installation, pod scheduling, and ArgoCD
manifest parsing. Its ECR and RDS emulation has no data plane, so the API pod is expected to remain
not-ready. Kind runs the built API image with PostgreSQL in an isolated Kubernetes cluster and
exercises health, readiness, and HTTP CRUD through the API Service. Real AWS remains the check for
ALB, ECR, RDS, IAM, VPC, and production networking.
- **Acceptance:** make floci-validate passes shape checks; make kind-e2e passes health/readiness and
  create/list/get/update/delete/post-delete-404; docs/runbook-aws.md covers AWS behavior.

### E10 — Docs: runbooks + AI deliverable
docs/runbook-aws.md covers the real-AWS deployment path; docs/floci.md and docs/kind.md explain complementary local validation; docs/architecture.md records system decisions; docs/ai-assistant.md captures the AI deliverable and validation history.
- **Acceptance:** reviewers can follow the AWS runbook and local checks; docs match validated behavior and limits.

## Non-goals (out of scope)

- Live AWS apply in this exercise (the real-account path is a ready-to-run runbook).
- Floci as a performance/billing proxy.
- A production migration tool (the sample uses an idempotent bootstrap instead).
