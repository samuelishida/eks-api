# Architecture

## Diagram

```mermaid
flowchart LR
    subgraph Internet
        C[Client]
    end

    subgraph AWS["AWS (us-east-1)"]
        subgraph VPC["VPC 10.x.0.0/16"]
            subgraph PUB["Public subnets"]
                IGW[Internet Gateway]
                NAT[NAT Gateway]
                ALB[ALB<br/>via AWS LBC]
            end
            subgraph PRIV["Private subnets"]
                subgraph EKS["EKS cluster (private endpoint)"]
                    NS[ns api-<env>]
                    P1[API replica 1<br/>:8080]
                    P2[API replica 2<br/>:8080]
                    LBC[AWS Load Balancer<br/>Controller (IRSA)]
                    ACD[ArgoCD<br/>app-of-apps]
                end
                RDS[(RDS PostgreSQL<br/>private-only<br/>KMS-encrypted)]
                VPE[VPC Endpoints<br/>S3 / EC2 / STS]
            end
        end
        ECR[ECR eks-api-api-{env}<br/>scan-on-push]
        CW[CloudWatch<br/>alarms -> SNS]
        S3B[(S3 state bucket<br/>+ DynamoDB lock)]
    end

    C -->|HTTPS :443| ALB
    ALB -->|ip-target :8080| P1
    ALB -->|ip-target :8080| P2
    P1 -->|node-group SG -> RDS SG :5432| RDS
    P2 -->|node-group SG -> RDS SG :5432| RDS
    LBC -->|manages| ALB
    ACD -->|syncs chart| NS
    IGW --- ALB
    NAT --- IGW
    EKS -.->|node pull| ECR
    P1 -.->|logs| CW
    RDS -.->|metrics| CW
    ALB -.->|5xx| CW
    CW -->|SNS topic <name>-<env>-alerts| SNS[(SNS)]
    S3B -.->|remote state| TF[Terraform envs]
```

Everything the database touches is inside the VPC: RDS has **no public
address**, its security group accepts only traffic from the dedicated workload
node group, and nodes pull images via NAT/VPC endpoints. Standard VPC CNI pods
share node ENIs, so this is a node-level boundary, not per-pod isolation. The
only internet-facing object is the ALB.

## Decisions (D1–D8)

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | **ALB via AWS Load Balancer Controller (v3.6.0)**, IP targeting | AWS-native path for EKS; LBC runs in-cluster with an IRSA role and creates ALB + target groups from the `Ingress`. |
| D2 | **RDS PostgreSQL, private-only, write-only password** | `password_wo` (random_password) means password is managed in Terraform state and a Kubernetes Secret; no `master_password` in tfvars. SG ingress is sourced from the managed workload node group. KMS grants are restricted to RDS in the configured region. |
| D3 | **Multi-env Terraform: `modules/` + `environments/{dev,staging,prod,floci}`** | One reusable module set; each real env is an isolated root with its own S3+DynamoDB backend and tfvars. Floci uses local state. Kubernetes resources apply after the EKS bootstrap phase so provider configuration uses a live endpoint. |
| D4 | **Custom Helm chart `charts/api/`** | Values per env (`values-{dev,staging,prod}.yaml`), `secretExistingName` for the DB creds (chart never creates the secret), ALB Ingress with per-env className/scheme/TLS. |
| D5 | **ArgoCD app-of-apps (v3.5.5)** | `AppProject` + `Application` for LBC and one per env; auto-sync with prune + self-heal; `createNamespace: true`. The git repo is the single source of truth. |
| D6 | **Go API (chi + pgx), multi-stage distroless, non-root** | Small binary, no runtime deps; runs as uid 65532; `/healthz` + `/readyz` probes. |
| D7 | **Floci + Kind for complementary local validation** | Floci applies Terraform and checks AWS resource shape, chart installation, and ArgoCD parsing. Kind runs the API image against PostgreSQL and exercises health/readiness/CRUD through the Kubernetes Service. Neither proves AWS ALB, ECR, RDS, IAM, VPC, or production networking (see docs/floci.md, docs/kind.md, docs/runbook-aws.md). |
| D8 | **CloudWatch logs + alarms → SNS** | ALB 5xx, RDS CPU + free storage, node count, control-plane errors; per-env SNS topic `<name>-<env>-alerts`; `TreatMissingData` not breaching. See `docs/monitoring.md`. |

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
  charts/api/                   # custom Helm chart (+ per-env values)
  apps/
    api/                        # Go API (multi-stage, distroless, non-root)
    argocd/                     # per-cluster roots + AppProject, LBC and API Applications
  examples/node-service/        # second sample Dockerfile (reference only)
  .github/workflows/            # build, deploy, terraform, provenance-gate
  docs/                         # user-story, architecture, runbook, monitoring, floci, kind, ai-assistant
  Makefile
```

## Data flow (request)

1. Client → ALB (HTTP in dev; HTTPS with ACM in staging/prod) → target group (IP target `:8080`).
2. Pod (one of N replicas) → `pgx` → RDS over the private network
   (workload node SG → RDS SG, `:5432`). Other pods scheduled on those nodes share that network access.
3. Logs → CloudWatch; 5xx/CPU/storage/node-count/control-plane → alarms → SNS.

## GitOps flow (change)

1. `main` push → `build.yml`: `go vet` + `go test` → buildx push
   the same `<sha>` tag to each environment ECR repository (OIDC, no long-lived keys).
2. `deploy.yml` (workflow_run, gated on success + `main`): opens a PR bumping
   `image.tag` in the env's values file.
3. Merge → ArgoCD auto-syncs → rolling update. `provenance-gate.yml` fails
   `main` pushes without a merge commit (no force-pushes).
