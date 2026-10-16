# eks-api — Production-Grade EKS Deployment (Terraform + Helm + GitOps)

A complete, idiomatic, production-shaped repository that deploys a containerized API to
**AWS EKS**, where:

- the **API uses an ALB** (internal in dev, internet-facing in staging/prod),
- the **database is private** and accepts connections from the managed workload node group,
- the **DB has persistent storage** (RDS PostgreSQL) and the app runs with **several replicas**,
- **EKS** is the orchestrator, and the work follows best practice for Terraform, Helm, and GitOps.

## Architecture (one paragraph)

Each real environment (`dev`, `staging`, `prod`) is an isolated Terraform root with its own
S3+DynamoDB remote backend and tfvars. Floci uses local state. Shared modules under
`terraform/modules/` build a VPC (public + private subnets, one shared NAT), an EKS cluster with
**private-only** endpoint access and a managed node group (both `AmazonEKSWorkerNodePolicy` and
`AmazonEKS_CNI_Policy` attached), a private-only RDS PostgreSQL (write-only password, KMS key,
inbound SG rule sourced from the dedicated workload node group), an ECR repository (scan-on-push), and a monitoring
module (EKS control-plane logs + alarms → SNS). The API is a small Go service (chi + pgx) packaged as a
custom Helm chart (`charts/api/`) with an ALB `Ingress` (AWS Load Balancer Controller, ip-targeting).
CI (GitHub Actions, OIDC) builds + pushes the image to ECR tagged with the git SHA and opens a PR that
bumps `image.tag`; **ArgoCD** (app-of-apps) syncs the chart on merge. The git repo is the single source
of truth.

## Repo layout

```
eks-api/
  terraform/
    versions.tf                 # pinned providers + modules
    modules/                    # vpc, eks, rds, network, ecr, monitoring, lbc
    environments/
      bootstrap/                # one-off: S3 state bucket + DynamoDB lock table
      dev|staging|prod/         # real S3+DynamoDB backend + tfvars per env
      floci/                    # local-only, points at the Floci emulator
  charts/api/                   # custom Helm chart for the API (+ per-env values)
  apps/
    api/                        # Go API (multi-stage, distroless, non-root)
    argocd/                     # ArgoCD per-cluster roots (LBC + API Application)
  examples/node-service/        # second sample Dockerfile (Node, reference only)
  .github/workflows/            # build, deploy, terraform, provenance-gate
  docs/                         # user-story, runbook, architecture, monitoring, floci, kind, ai-assistant
  Makefile
```

## Quickstart

Run both local validators; neither needs an AWS account:

```sh
make floci-up          # start Floci AWS control-plane emulator
make floci-validate    # check Terraform/AWS resource shape and Kubernetes manifests
make kind-e2e          # run API + PostgreSQL in Kind; exercise health and CRUD over HTTP
make floci-down
```

Floci checks AWS resource wiring. Kind runs the real API image against real PostgreSQL. Together they cover infrastructure shape plus the application data path; real AWS is still needed to validate ALB, ECR, RDS, IAM, VPC, and production networking.

Deploy to a real AWS account:

```sh
make tf-init ENV=dev   # bootstrap state first — see docs/runbook-aws.md
make tf-cluster-plan ENV=dev
make tf-cluster-apply ENV=dev  # first phase: VPC + EKS
make tf-plan ENV=dev           # full plan after cluster exists
make tf-apply ENV=dev
```

See [`docs/runbook-aws.md`](docs/runbook-aws.md) for the full real-AWS path,
[`docs/floci.md`](docs/floci.md) for AWS resource-shape checks, and
[docs/kind.md](docs/kind.md) for local API-to-PostgreSQL E2E.

## Docs

- [`docs/user-story.md`](docs/user-story.md) — the epic (task breakdown for this deployment).
- [`docs/architecture.md`](docs/architecture.md) — diagram + decisions.
- [`docs/runbook-aws.md`](docs/runbook-aws.md) — real-AWS apply, ready to run.
- [`docs/monitoring.md`](docs/monitoring.md) — what is alerted, where logs land.
- [docs/floci.md](docs/floci.md) — AWS control-plane shape validation with Floci.
- [docs/kind.md](docs/kind.md) — local API + PostgreSQL end-to-end validation with Kind.
- [`docs/ai-assistant.md`](docs/ai-assistant.md) — the Generative-AI deliverable.

## Notes

- RDS security group is scoped to the workload node group. Standard VPC CNI pods share node ENIs;
  any pod on those nodes can reach RDS. This is not per-pod Security Groups for Pods isolation.
- Floci is an AWS resource **shape** validator, not an EKS data-plane or application-traffic emulator.
- `ingress-nginx` was **not** used (repo archived/retiring); the ALB via the AWS Load Balancer
  Controller is the AWS-native path.
