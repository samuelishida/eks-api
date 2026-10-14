# Floci — local shape validation

Floci (the local AWS emulator in `aws-tools/local-emulator/`) is used for
**shape validation only**: a real `terraform apply` runs against the emulated
AWS control plane (backed by a real k3s cluster), and the Helm chart + ArgoCD
manifests are dry-run applied to that cluster.

**Floci does NOT validate end-to-end traffic.** Its ECR and RDS are
control-plane only (no data plane): the API pod is expected to sit in
`ImagePullBackOff`/not-ready. End-to-end traffic validation is the real-AWS
runbook's job (`docs/runbook-aws.md`).

## Prerequisites

- Floci emulator running: `make floci-up` (or `cd ../aws-tools/local-emulator && docker compose up -d`).
- `FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true` must be exported before `terraform apply` — the k3s cluster Floci creates has no default StorageClass, and without it PVCs (helm/ArgoCD) never bind.
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

## 2. Terraform apply

```sh
cd eks-api
export FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true
terraform -chdir=terraform/environments/floci init
terraform -chdir=terraform/environments/floci apply -auto-approve
```

State is local (`terraform.tfstate`) — the floci env has no S3 backend, intentionally. This creates the VPC, EKS (k3s-backed, control plane), RDS, network, ECR, monitoring, the LBC IRSA role, and the k8s namespace `api-floci` + `api-db-credentials` Secret.

**Floci-only guards (shape, not real-env changes):** Floci's IAM has no AWS-managed policies, so `lbc.tf` guards the `AmazonEKSLoadBalancerControllerPolicy` attachment behind `var.lbc_create_aws_managed_policy` (default `true` → dev/staging/prod unchanged; `false` in the gitignored `floci.auto.tfvars`). The inline LBC policy already carries the actions, so shape is preserved.

**EKS `--version` quirk:** `--version` is a *global* `aws` CLI flag, so any EKS `--version` must go via `--cli-input-json`. The eks module uses the provider's `aws_eks_cluster` resource (no `local-exec`), so this does not bite — documented here so a future `local-exec`-based change does not regress it.

## 3. Kubeconfig for the terraform-created cluster

The emulator dir's `kubeconfig` points at the pre-existing `demo` cluster, NOT the one terraform creates. Generate one for `eks-api-floci`:

```sh
cd ../aws-tools/local-emulator
./awslocal eks update-kubeconfig --name eks-api-floci --alias eks-api-floci --kubeconfig /tmp/floci-eks-api-kubeconfig
export KUBECONFIG=/tmp/floci-eks-api-kubeconfig
export AWS_PROFILE=floci     # the kubeconfig's `aws eks get-token` exec inherits this (clean env)
kubectl get nodes            # must show the eks-api-floci node
```

## 4. Shape checks (chart + ArgoCD)

```sh
cd eks-api
# Chart renders + server-side dry-run applies to the live k3s:
helm template api charts/api -f charts/api/values-dev.yaml | kubectl apply --dry-run=server -f -

# ArgoCD app-of-apps client dry-run (Project + LBC + 3 api Applications + 3 Namespaces):
kubectl apply --dry-run=client -f apps/argocd/
```

Both must exit 0. The ArgoCD dry-run resolves `Application`/`AppProject` only if the ArgoCD CRDs exist on the cluster — install them once (shape check only, no ArgoCD controller):

```sh
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/crds/application-crd.yaml \
              -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/crds/appproject-crd.yaml
```

(Without the CRDs, use `kubectl apply --dry-run=client --validate=false` — the Namespaces resolve, the CRD objects are skipped.) This dry-run is the Deployment/Ingress proof for shape validation — no real `helm install` is required. (If you do `helm install` for a stronger check, the pod is EXPECTED to be `ImagePullBackOff`/not-ready: **Scheduled is the success signal, not Running**. Do not fake the registry.)

## 5. Confirm created objects

```sh
kubectl get ns api-floci
kubectl get secret api-db-credentials -n api-floci
```

The Secret must exist with keys `host,port,user,password,name`.

## 6. Teardown

```sh
cd ../aws-tools/local-emulator
./awslocal eks delete-cluster --name eks-api-floci
docker compose down
```

Or: `make floci-down` (stops the emulator; delete the cluster first if you want the emulated EKS gone too).
