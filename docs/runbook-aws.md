# Runbook — deploying eks-api to AWS

This runbook provisions separate `dev`, `staging`, and `prod` environments. It
creates private EKS control-plane endpoints, private RDS PostgreSQL, ECR, an
AWS Load Balancer Controller IRSA role, and CloudWatch alerts. Account IDs,
domains, repository names, and role ARNs are placeholders until configured.

Floci checks local Terraform/Helm/Kubernetes resource wiring. Kind checks live
API-to-PostgreSQL traffic and CRUD. Neither proves AWS networking, IAM,
availability, performance, or cost; this runbook covers real AWS behavior.

## Prerequisites

- AWS account and Terraform execution role with required EKS, EC2, IAM, KMS,
  RDS, ECR, CloudWatch, SNS, S3, DynamoDB, and ACM permissions.
- Terraform `>= 1.11`, AWS CLI v2, Helm, kubectl, Docker, and GitHub Actions OIDC.
- A Terraform runner inside the VPC (or connected by VPN/SSM) for each apply:
  EKS API endpoints are private, and Terraform also writes Kubernetes Secrets.
- GitHub repository with Actions variables `AWS_ACCOUNT_ID`, `AWS_REGION`,
  and `AWS_BUILD_ROLE_ARN` configured.

Use `AWS_PROFILE=<profile>` for local AWS CLI and Terraform commands as needed.

## 1. Create remote state backend

Bootstrap root uses local state. Initialize it before applying:

```sh
export STATE_BUCKET=eks-api-tfstate-<account-id>
export LOCK_TABLE=eks-api-tflock

terraform -chdir=terraform/environments/bootstrap init
terraform -chdir=terraform/environments/bootstrap apply \
  -var="state_bucket=$STATE_BUCKET" \
  -var="lock_table=$LOCK_TABLE" \
  -var="region=us-east-1"
```

For each real environment, copy its backend example to ignored `backend.hcl`
and set the bucket name. Keep environment-specific `key`, region, and lock table:

```sh
cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl
```

Staging and prod var files are intentionally untracked. Copy
`terraform/environments/dev/dev.tfvars` to
`terraform/environments/staging/staging.tfvars` and
`terraform/environments/prod/prod.tfvars`, then set `env_name`, region,
CIDR, availability zones, and sizing values for each environment. Keep each
environment's settings separate. Set `alert_email` in the production tfvars if
CloudWatch notifications should reach an operator; confirm SNS subscription
email after apply. `backend.hcl` is not Terraform input; do not put backend
settings in `.tfvars`.

## 2. Plan and apply each environment

Run each environment from a runner that can reach its private EKS endpoint:

```sh
make tf-init ENV=dev
make tf-cluster-plan ENV=dev
# Review, then create VPC + EKS first. Kubernetes provider needs live cluster data.
make tf-cluster-apply ENV=dev
make tf-plan ENV=dev
# Inspect full plan, then:
make tf-apply ENV=dev
```

Repeat both plan/apply phases for staging and prod after creating their backend
and tfvars files. Terraform's Kubernetes provider depends on live EKS endpoint
data, so the first targeted VPC/EKS apply makes that provider configuration
available; the second full apply creates RDS, ECR, monitoring, the DB Secret,
and LBC IRSA role. Prod enables
Multi-AZ RDS, deletion protection, and longer backups. Review each plan before
applying; environment name changes can require resource replacement if state
already exists.

Record these outputs for later steps:

```sh
terraform -chdir=terraform/environments/dev output
```

Use `vpc_id`, `cluster_name`, `ecr_repository_url`, `lbc_role_arn`,
`acm_certificate_arn`, and `acm_validation_options` as applicable.

## 3. Configure CI permissions

Configure GitHub OIDC trust for the repository. Build role needs ECR push
permissions on all three repositories (`eks-api-api-dev`,
`eks-api-api-staging`, `eks-api-api-prod`) plus `ecr:GetAuthorizationToken`.
Deploy workflow uses `GITHUB_TOKEN` to open/update the dev image PR and does not
need AWS credentials. Restrict role trust to the repository and intended branch
or workflow subject.

Set GitHub repository variables:

- `AWS_ACCOUNT_ID`: 12-digit AWS account ID.
- `AWS_REGION`: region used by Terraform/ECR.
- `AWS_BUILD_ROLE_ARN`: OIDC role ARN allowed to push those ECR repos.

## 4. Install ArgoCD and select environment root

Install ArgoCD privately from a runner with cluster access. Chart `10.10.3`
uses ArgoCD app version `3.5.5`:

```sh
aws eks update-kubeconfig --name eks-api-dev --region "$AWS_REGION"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 10.10.3 \
  -f apps/argocd/argocd-values.yaml
```

Keep ArgoCD server internal; use a private access path such as:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Add read-only Git credentials in ArgoCD if the repository is private. In only
the selected environment's root and child manifests, replace `<org>`, LBC IRSA
role ARN, VPC ID, and region with real values. Replace the region in the LBC
chart values too. Apply one root per cluster:

```sh
kubectl apply -f apps/argocd/root-dev.yaml
```

Use `root-staging.yaml` or `root-prod.yaml` only against its matching cluster.
The root applies its scoped AppProject, then the LBC and API Applications.

## 5. Validate ACM DNS and enable TLS

Staging and prod request ACM DNS-validated certificates. Terraform outputs
`acm_validation_options`; it does not create Route53 records or wait for
issuance. Create each listed CNAME in the authoritative DNS zone and wait until
ACM reports `ISSUED`. Then update that environment's
`charts/api/values-<env>.yaml` `ingress.certArn` with the output ARN and merge
the reviewed change. Dev currently uses an internal ALB without TLS.

## 6. Deploy and smoke-check API

Set `image.repository` in `charts/api/values-<env>.yaml` to that environment's
Terraform `ecr_repository_url` output (the checked-in account and region are
placeholders). Keep `image.tag` as an immutable commit SHA.

Push to `main`. Build workflow runs `go vet` and `go test`, then pushes the
same immutable commit SHA to each environment's ECR repository. A successful
build opens a PR updating dev's `image.tag`; merge it to deploy dev. Promote
that exact SHA to staging and prod with reviewed PRs to their values files.

Check rollout and ingress from a network that can reach the private cluster:

```sh
kubectl -n api-dev get deploy,service,ingress
kubectl -n api-dev rollout status deployment/api
```

Check `/healthz` and `/readyz` through the ALB after ingress has an address.
`/healthz` proves process liveness; `/readyz` proves DB connectivity and schema
bootstrap completed.

## 7. ACM / ingress and troubleshooting

| Symptom | Likely cause / action |
| --- | --- |
| `terraform init` fails | Bootstrap state bucket/table first; check ignored `backend.hcl` values. |
| Terraform Kubernetes provider cannot connect | Run from inside VPC or a connected VPN/SSM host; cluster endpoint is private. |
| ALB not created | Check LBC Application health, IRSA role ARN, VPC ID, chart version, and controller logs. |
| TLS listener missing | ACM DNS CNAME not created, certificate not `ISSUED`, or `ingress.certArn` is still placeholder. |
| API pod not ready | Check Secret `api-db-credentials`, RDS endpoint/security groups, pod logs, and `/readyz`. |
| ECR image pull fails | Check image repository/account/region, build role permissions, SHA tag, and node ECR access. |
| ArgoCD cannot read Git repo | Add read-only repo credentials and verify `<org>`/repo URL. |

## 8. Teardown

Remove the matching ArgoCD root/Application first so GitOps stops reconciling.
Then review and destroy that environment from a private-network runner:

```sh
kubectl -n argocd delete application eks-api-dev
make tf-destroy ENV=dev
```

Only destroy the bootstrap root after all environment states are removed.
