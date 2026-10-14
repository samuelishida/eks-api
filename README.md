# eks-api — Production-Grade EKS Deployment (Terraform + Helm + GitOps)

A complete, idiomatic, production-shaped repository that deploys a containerized API to
**AWS EKS**, where:

- the **API is reachable from outside** the cluster/account (via an ALB),
- the **database is NOT reachable from outside** — only the API talks to it, over the private
  network,
- the **DB has persistent storage** (RDS PostgreSQL) and the app runs with **several replicas**,
- **EKS** is the orchestrator, and the work follows best practice for Terraform, Helm, and GitOps.

## Architecture (one paragraph)

Each environment (`dev`, `staging`, `prod`, plus a local-only `floci`) is an isolated Terraform
root with its own S3+DynamoDB remote backend and `tfvars`. Shared, reusable modules under
`terraform/modules/` build a VPC (public + private subnets, one shared NAT), an EKS cluster with
**private-only** endpoint access and a managed node group (both `AmazonEKSWorkerNodePolicy` and
`AmazonEKS_CNI_Policy` attached), a private-only RDS PostgreSQL (write-only password, least-privilege
KMS key, SG reachable only from the pod SG), an ECR repository (scan-on-push), and a monitoring
module (CloudWatch logs + alarms → SNS). The API is a small Go service (chi + pgx) packaged as a
custom Helm chart (`charts/api/`) with an ALB `Ingress` (AWS Load Balancer Controller, ip-targeting).
CI (GitHub Actions, OIDC) builds + pushes the image to ECR tagged with the git SHA and opens a PR that
bumps `image.tag`; **ArgoCD** (app-of-apps) syncs the chart on merge. The git repo is the single source
of truth.

## Repo layout

```
eks-api/
  terraform/
    versions.tf                 # pinned providers + modules
    modules/                    # vpc, eks, rds, network, ecr, monitoring
    environments/
      dev|staging|prod/         # real S3+DynamoDB backend + tfvars per env
      floci/                    # local-only, points at the Floci emulator
  charts/api/                   # custom Helm chart for the API (+ per-env values)
  apps/
    api/                        # Go API (multi-stage, distroless, non-root)
    argocd/                     # ArgoCD app-of-apps (LBC + per-env api Applications)
  examples/node-service/        # second sample Dockerfile (Node, reference only)
  .github/workflows/            # build, deploy, terraform, provenance-gate
  docs/                         # user-story (epic), runbook, architecture, monitoring, floci, ai-assistant
  Makefile
```

## Quickstart

Validate locally against the [Floci](https://floci.dev) AWS emulator (no AWS account, no cost):

```sh
make floci-up          # start Floci (aws-tools/local-emulator) with a k3s-backed EKS cluster
make floci-validate    # terraform apply (floci) + helm/kubectl dry-runs + shape checks
make floci-down
```

Deploy to a real AWS account:

```sh
make tf-init ENV=dev   # bootstrap state first — see docs/runbook-aws.md
make tf-plan ENV=dev
make tf-apply ENV=dev
```

See [`docs/runbook-aws.md`](docs/runbook-aws.md) for the full real-AWS path and
[`docs/floci.md`](docs/floci.md) for local validation.

## Docs

- [`docs/user-story.md`](docs/user-story.md) — the epic (task breakdown for this deployment).
- [`docs/architecture.md`](docs/architecture.md) — diagram + decisions.
- [`docs/runbook-aws.md`](docs/runbook-aws.md) — real-AWS apply, ready to run.
- [`docs/monitoring.md`](docs/monitoring.md) — what is alerted, where logs land.
- [`docs/floci.md`](docs/floci.md) — local validation with the Floci emulator.
- [`docs/ai-assistant.md`](docs/ai-assistant.md) — the Generative-AI deliverable.

## Notes

- Floci is a **shape** validator (manifest/TF correctness), **not** a performance or billing proxy.
- `ingress-nginx` was **not** used (repo archived/retiring); the ALB via the AWS Load Balancer
  Controller is the AWS-native path.
