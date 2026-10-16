# ArgoCD app-of-apps

Each EKS cluster gets one environment root (`root-dev.yaml`, `root-staging.yaml`,
or `root-prod.yaml`). Apply only the matching root to that cluster. The root
creates a scoped `AppProject`, then reconciles the AWS Load Balancer Controller
and that cluster's API chart. This keeps dev, staging, and prod clusters from
deploying each other's workloads.

## Bootstrap

1. Install ArgoCD chart `argo/argo-cd` version `10.10.3` (app version `3.5.5`)
   with `argocd-values.yaml`. This restores health reporting for child
   `Application` resources, which makes the sync waves below wait for LBC
   health before syncing the API app.
2. Add read-only credentials for this Git repository to ArgoCD if it is private.
3. Replace `<org>` in the selected root, project, and API app manifests.
4. Replace the LBC role ARN and VPC ID with that environment's Terraform
   outputs, then apply the matching root manifest:

   ```sh
   kubectl apply -f apps/argocd/root-dev.yaml
   ```

The root app path is environment-scoped under `environments/<env>/`. It applies
the project at wave `-2`, LBC at wave `-1`, then API at wave `0`. ArgoCD's
Application health customization is required for those waves to wait for child
apps to become healthy.

## Promotion

- **dev**: successful builds on `main` open a PR that updates
  `charts/api/values-dev.yaml` to the immutable image SHA. Merge that PR to
  deploy.
- **staging/prod**: promote the same SHA with reviewed PRs to the corresponding
  values file. CI pushes that SHA to each environment's ECR repository.

Terraform creates one ECR repository and one LBC IRSA role per environment.
The LBC chart uses the official `https://aws.github.io/eks-charts` repository
and creates its annotated ServiceAccount itself.
