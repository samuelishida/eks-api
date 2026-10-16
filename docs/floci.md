# Floci — local shape validation

Floci (the local AWS emulator in `aws-tools/local-emulator/`) is used for
**shape validation only**: `make floci-validate` applies Terraform against the
emulated AWS control plane (backed by k3s), server-side dry-runs then installs
the API Helm release, waits for pod scheduling, and parses environment-scoped
ArgoCD manifests.

**Floci does NOT validate end-to-end traffic.** Its ECR and RDS are
control-plane only (no data plane): the API pod is expected to sit in
`ImagePullBackOff`/not-ready. Use [Kind](kind.md) to run the real API image
against PostgreSQL and exercise HTTP CRUD locally. Use the real-AWS runbook
(`docs/runbook-aws.md`) to validate AWS EKS, ECR, RDS, ALB, IAM, VPC, and
production networking.

## Prerequisites

- Floci emulator running: `make floci-up` (or `cd ../aws-tools/local-emulator && docker compose up -d`).
- The validation script enables `FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true` for Terraform apply.
- The scoped CLI wrapper `./awslocal` (in the emulator dir) is the ONLY way to talk to Floci from the `aws` CLI. **Never `export AWS_ENDPOINT_URL`** in your shell — the wrapper scopes the endpoint to the child `aws` process only.
- A named `floci` AWS profile carrying the endpoint (needed by kubectl's `aws eks get-token` exec, which runs in a clean env): `~/.aws/credentials` `[floci]` must have `aws_access_key_id`, `aws_secret_access_key`, `region`, and `endpoint_url = http://localhost:4566`.

## 1. Credentials (gitignored tfvars)

The Floci EKS auth webhook rejects `test`/`test`. Create `terraform/environments/floci/floci.auto.tfvars` (gitignored) from the emulator's `.env`:

```sh
cd aws-tools/local-emulator
grep -E 'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)' .env
```

```hcl
# terraform/environments/floci/floci.auto.tfvars (gitignored)
floci_access_key = "<AKID from .env>"
floci_secret_key = "<secret from .env>"
```

`floci_k8s_token` defaults to `"floci"` in `variables.tf`; for the real k3s the kubernetes provider needs a valid token — pass `TF_VAR_floci_k8s_token="$(./awslocal eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token')"` at apply time (see `Makefile floci-validate`). Verify the tfvars is gitignored: `git check-ignore terraform/environments/floci/floci.auto.tfvars`.

## 2. Terraform apply and chart install

```sh
cd eks-api
make floci-validate
```

State is local (`terraform.tfstate`) — the floci env has no S3 backend,
intentionally. The script first applies VPC/EKS so Terraform's Kubernetes
provider has a live endpoint, then applies RDS, network, ECR, LBC IRSA role,
namespace, and DB Secret. It then installs the API chart into
`api-floci` and confirms its pod reaches `PodScheduled`.

Floci uses RDS `gp2`: its emulator does not apply storage-type updates. Real
AWS environments keep RDS `gp3` by default. Floci leaves its default network
ACL unmanaged because the emulator does not round-trip IPv6 ACL rules reliably;
real environments retain managed ACLs. Floci also preserves a legacy ingress
rule description because its API ignores description updates. The rule still
uses the workload node-group security boundary; descriptions have no effect.

Floci does not run the AWS data plane. The placeholder ECR image is expected to
fail image pull; `PodScheduled` proves Kubernetes accepted and scheduled the
workload, not that the API is running or reachable.

The LBC IAM role uses the same versioned AWS policy document as real
environments. Floci Terraform state has moved blocks for the former root-level
role/policy addresses to preserve existing local state.

**EKS `--version` quirk:** `--version` is a *global* `aws` CLI flag, so any EKS `--version` must go via `--cli-input-json`. The eks module uses the provider's `aws_eks_cluster` resource (no `local-exec`), so this does not bite — documented here so a future `local-exec`-based change does not regress it.

## 3. Kubeconfig for the terraform-created cluster

The validation script writes a static-token kubeconfig to
`/tmp/floci-eks-api-kubeconfig`; it does not use the emulator's default
`demo`-cluster kubeconfig. To inspect the cluster:

```sh
cd ../aws-tools/local-emulator
export KUBECONFIG=/tmp/floci-eks-api-kubeconfig
kubectl get nodes            # must show the eks-api-floci node
```

## 4. Shape checks (chart + ArgoCD)

```sh
cd eks-api
# The validation script runs server-side dry-run, installs the chart, and waits for scheduling:
helm template api charts/api -f charts/api/values-dev.yaml | kubectl apply --dry-run=server -f -
helm upgrade --install api charts/api --namespace api-floci --create-namespace -f charts/api/values-dev.yaml
kubectl -n api-floci wait --for=condition=PodScheduled pod -l app.kubernetes.io/instance=api --timeout=120s

# Script parses each environment root and child manifests without requiring AWS/Argo CRDs:
for env in dev staging prod; do kubectl apply --dry-run=client --validate=false -f "apps/argocd/root-$env.yaml" -f "apps/argocd/environments/$env"; done
```

Script success proves Terraform apply converged in Floci, chart resources were
accepted, the release installed, the pod was scheduled, and Argo manifests
parsed. It does not prove image pull, API readiness, ingress provisioning, or
real AWS behavior. The complementary Kind check in [docs/kind.md](kind.md)
covers the local API-to-PostgreSQL data path.

## 5. Confirm created objects

```sh
kubectl get ns api-floci
kubectl get secret api-db-credentials -n api-floci
```

The Secret must exist with keys `host,port,user,password,name`.

## 6. Teardown

```sh
export KUBECONFIG=/tmp/floci-eks-api-kubeconfig
helm uninstall api -n api-floci
make tf-destroy ENV=floci
make floci-down
```

`make floci-down` only stops the emulator. Destroy Floci Terraform state first
if you want the emulated AWS resources removed too.
