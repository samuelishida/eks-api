# Runbook — deploying eks-api to a real AWS account

This runbook takes the validated repo from a fresh AWS account to a live,
ALB-fronted API on EKS with a private RDS PostgreSQL, per environment
(`dev` → `staging` → `prod`). All account-specific values are **placeholders**
(`<account-id>`, `<your-org>`); substitute your own — nothing here is a secret.

> **Floci is a shape validator, not a billing proxy.** `make floci-validate`
> proves the Terraform/Helm/k8s wiring is coherent; it does not prove cost,
> performance, or real network behavior. Only this runbook (real AWS) does that.

## 0. Prerequisites

| What | Why | How to check |
| --- | --- | --- |
| AWS account + IAM user/role with admin (or EKS/RDS/IAM/S3/ECR/CloudWatch) perms | everything below | `aws sts get-caller-identity` |
| `aws` CLI v2 + `terraform` ≥ 1.11 + `helm` + `kubectl` + `docker` | toolchain | `terraform -version` etc. |
| GitHub repo with this code pushed | CI/CD + ArgoCD source | — |
| GitHub OIDC: the repo's Actions can assume AWS roles (steps 3–4) | CI builds/pushes images, opens deploy PRs | — |
| ACM-validated certificate (prod/staging only) | TLS on the ALB | see step 5 |

Set a profile alias used throughout: `export AWS_PROFILE=<your-profile>`.

## 1. Step 0 — bootstrap remote state (chicken-and-egg)

Every env's `terraform init` reads its state from S3 with a DynamoDB lock table,
so those must exist **before** the first env `init`. They live in a one-off
root:

```sh
# 1a. Pick a globally-unique bucket name (S3 names are global — include your account ID).
#     e.g. eks-api-tfstate-123456789012
export STATE_BUCKET=eks-api-tfstate-<account-id>
export LOCK_TABLE=eks-api-tflock

# 1b. Apply the bootstrap root (S3 bucket: versioned, KMS-encrypted, public-access
#     blocked, noncurrent-expiration; DynamoDB: PAY_PER_REQUEST + PITR).
terraform -chdir=terraform/environments/bootstrap apply -auto-approve \
  -var state_bucket="$STATE_BUCKET" -var lock_table="$LOCK_TABLE"

# 1c. Point each env at the new backend (the tracked tfvars ship a placeholder):
#     in terraform/environments/{dev,staging,prod}/*.tfvars set
#       backend_bucket = "<$STATE_BUCKET>"
#       lock_table     = "<$LOCK_TABLE>"
#     (dev.tfvars is tracked; staging/prod tfvars are gitignored — create them
#      from dev.tfvars and adjust `env_name`.)
```

Do **not** destroy the bootstrap root while any env still references the
bucket/table — their `init` would fail.

## 2. Per-env apply order

For each environment (`dev` first), from the repo root:

```sh
make tf-init ENV=dev      # terraform init (S3+DynamoDB backend)
make tf-plan ENV=dev      # review the plan
make tf-apply ENV=dev     # apply
```

The env root applies its modules in dependency order automatically
(`main.tf` → vpc → eks → network → rds → ecr → monitoring; `lbc.tf` → LBC IRSA
role). There is nothing to run by hand between them — one `apply` per env.
What the apply creates, in order:

1. **VPC** — public + private subnets, one NAT gateway (shared), VPC endpoints.
2. **EKS** — cluster with **private-only** endpoint access, managed node group
   (both `AmazonEKSWorkerNodePolicy` and `AmazonEKS_CNI_Policy` attached),
   OIDC provider (for IRSA), pod + node security groups.
3. **Network** — RDS security group (ingress **only** from the pod SG),
   ACM certificate + validation records (staging/prod).
4. **RDS** — PostgreSQL, **private-only** (no public address), write-only
   password (`random_password` → `password_wo`), KMS-encrypted, least-privilege
   KMS key policy.
5. **ECR** — `eks-api-api` repository, scan-on-push, lifecycle policy.
6. **Monitoring** — CloudWatch alarms (ALB 5xx, RDS CPU/storage, node count,
   control-plane errors) → SNS topic `<name>-<env>-alerts`.
7. **LBC** — IRSA role `eks-api-lbc-<env>` for the AWS Load Balancer Controller.

After apply, note the outputs: `cluster_endpoint`, `ecr_repository_url`,
`lbc_role_arn`, `rds_endpoint` (private), `sns_topic_arn`.

## 3. IAM for CI (OIDC)

Create two roles that trust the GitHub OIDC provider
(`token.actions.githubusercontent.com`), restricted to your repo:

- **build role** (`AWS_BUILD_ROLE_ARN` in `build.yml`): `ecr:GetAuthorizationToken`,
  `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`,
  `ecr:PutImage` on the `eks-api-api` repo.
- **deploy role** (`AWS_DEPLOY_ROLE_ARN` in `deploy.yml`): minimal — it only
  opens/updates the deploy PR via the GitHub API (no AWS writes needed beyond
  reading the image tag it just built).

The repo's **OIDC provider** must be registered with your account
(`aws iam create-open-id-connect-provider ...` with the standard Actions
thumbprints), and the role trust policies must pin `sub` to
`repo:<your-org>/eks-api:ref:refs/heads/main` (build) / `pull_request` (deploy).

## 4. ArgoCD install + repo credentials

ArgoCD is **not** installed by Terraform (it is the GitOps entry point). Install
it once, in the cluster the env points at:

```sh
# kubeconfig for the cluster (AWS CLI v2):
aws eks update-kubeconfig --name eks-api-<env> --profile <your-profile>

# Upstream chart, appVersion 3.5.5 (matches apps/argocd/*):
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set argocd.server.service.type=LoadBalancer \
  --version <chart-version-for-3.5.5>
```

Then give ArgoCD access to the git repo (repo credential, not a token in the
Application manifests): add the GitHub token as a **repo credential** in the
ArgoCD UI/CLI (or a `secret` in the `argocd` namespace with
`argocd.argoproj.io/secret-type: repo-creds`), scoped to read the repo. The
`AppProject` (`apps/argocd/argocd-project.yaml`) already pins
`sourceRepos` to this repo.

## 5. ACM certificate (staging/prod)

The `network` module creates the ACM certificate **and** its DNS-01 validation
records in your hosted zone. You must complete validation (CNAME records) —
either let the module create the CNAMEs (it emits `acm_validation` with the
FQDN/resource records) and apply them to your zone, or validate out-of-band.
Until the certificate is `ISSUED`, the ALB Ingress will not serve TLS.

## 6. First deploy

1. Push the repo to GitHub. The `build.yml` workflow runs on `main`:
   `go vet` + `go test` → buildx push of `eks-api-api:<sha>` to ECR.
2. `deploy.yml` (on build success) opens a PR bumping
   `charts/api/values-dev.yaml` `image.tag` to the new SHA. Review + merge.
3. ArgoCD detects the change (auto-sync, prune + self-heal) and rolls the
   `api-dev` deployment. Watch: `kubectl -n api-dev get deploy,ingress` and the
   ALB DNS from `kubectl -n api-dev get ingress -o wide`.
4. Smoke test: `curl https://<alb-dns>/healthz` and `/readyz`.
5. Repeat 2–4 for staging/prod (their `values-<env>.yaml` are bumped by
   hand/PR — `CODEOWNERS` routes staging/prod value changes to `@org/platform`).

## 7. Teardown

Per env, reverse order (ArgoCD app first so it doesn't re-create resources):

```sh
# Remove the ArgoCD Application (or let prune handle it on destroy):
kubectl -n argocd delete application api-<env>   # if it exists

make tf-destroy ENV=<env>
```

Finally, destroy the bootstrap root **only after** all envs are gone:

```sh
terraform -chdir=terraform/environments/bootstrap destroy
```

## 8. Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `terraform init` fails on backend | Bootstrap (step 1) not applied, or `backend_bucket`/`lock_table` in tfvars don't match the real names |
| ALB never becomes `Active` | LBC not installed (step 4) or IRSA role ARN in `apps/argocd/lbc.yaml` not substituted with the real `lbc_role_arn` |
| Ingress has no TLS | ACM cert not `ISSUED` (step 5) |
| API pods `CrashLoopBackOff` on DB | Secret `api-db-credentials` keys must be `host/port/user/password/name`; RDS SG must allow the pod SG |
| ArgoCD `Unknown host` on repo | Repo credential (step 4) missing/wrong |
| CI `unable to get password from user` (ECR login) | Build role (step 3) missing `ecr:*` on the repo, or OIDC trust `sub` too broad/narrow |
