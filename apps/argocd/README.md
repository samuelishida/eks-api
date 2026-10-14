# ArgoCD app-of-apps (Inc 6)

GitOps layer for the eks-api repo. The git repo is the single source of truth:
ArgoCD watches it and syncs the `AppProject` `eks-api` (this directory) into
the cluster.

## ArgoCD installation

ArgoCD itself is installed once per cluster from the upstream `argo-cd` Helm
chart (appVersion `3.5.5`), into its own `argocd` namespace. It is NOT
managed by this app-of-apps (it is the bootstrap tool, not a workload):

```sh
helm repo add https://argo-cd.readthedocs.io/
helm install argocd https://argo-cd.readthedocs.io/argo-cd \
  --version 3.55.5 --namespace argocd --create-namespace
```

Repo-credential provisioning (e.g. an `argocd` GitHub App / PAT stored as an
ArgoCD `Repo` secret) is covered by the runbook — see `docs/` and the
bootstrap runbook.

## How the app-of-apps works

Everything in this directory is synced by ArgoCD:

1. `argocd-project.yaml` — the `AppProject` `eks-api`: scopes source repos
   (this repo + the upstream LBC chart repo), destinations (in-cluster,
   `api-*` + `kube-system`), and a narrow cluster-resource whitelist
   (Namespaces + the LBC's ClusterRole/ClusterRoleBinding).
2. `lbc.yaml` — installs the **AWS Load Balancer Controller** from the
   official upstream chart (`v3.6.0`) into `kube-system`. **This must sync
   BEFORE the api applications**: the api chart's ALB `Ingress` is only
   reconciled once the controller is running.
3. `api-dev.yaml` / `api-staging.yaml` / `api-prod.yaml` — one `Application`
   per environment, each deploying `charts/api` with
   `valueFiles: [values.yaml, values-<env>.yaml]` (base first, then the env
   override). Each targets its own namespace (`api-dev`, `api-staging`,
   `api-prod`) with `createNamespace: true` + `syncOptions:
   CreateNamespace=true`, and `autoSync` with `prune` + `selfHeal`.
4. `namespace-<env>.yaml` — the `api-*` namespaces as the declarative source
   of truth (ArgoCD also creates them via `createNamespace`; the manifests
   keep the namespaces and their labels in git).

## Promotion policy

- **dev**: auto-syncs on `main` (any merge to `main` deploys to dev).
- **staging / prod**: promote via a separate, human-reviewed PR that bumps
  the image tag in `values-staging.yaml` / `values-prod.yaml` (Inc 7 wires
  the CI that opens that PR). Prod is never auto-synced from `main`.

## LBC IRSA role ARN placeholder

`lbc.yaml` sets
`serviceAccount.annotations."eks.amazonaws.com/role-arn"` to the placeholder
`arn:aws:iam::123456789012:role/eks-api-lbc-irsa`. **It must be replaced with
the Terraform output `lbc_role_arn`** (the env-level `aws_iam_role.lbc` in
`terraform/environments/<env>/lbc.tf`) for each real account before syncing.
The trust policy on that role federates the cluster's OIDC provider to the
`kube-system/aws-load-balancer-controller` service account, so the ARN and
the service account must match exactly.

## LBC egress path

The LBC (and the cluster's control plane) call the EC2/ELB/ECS APIs from the
**private** subnets. Those egress calls reach AWS through the **NAT gateway**
in the public subnets. Dropping the NAT gateway in prod would break the LBC
(it would no longer be able to manage the ALB) — keep the NAT even in
cost-optimized prod.
