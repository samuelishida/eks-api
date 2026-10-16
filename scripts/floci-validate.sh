#!/usr/bin/env sh
# floci-validate — terraform apply (floci) + helm/kubectl dry-runs + shape checks.
# Invoked from the repo root by `make floci-validate`.
set -eu

FLOCI_DIR="${FLOCI_DIR:-../aws-tools/local-emulator}"
FLOCI_KC="${FLOCI_KC:-/tmp/floci-eks-api-kubeconfig}"
CHART="${CHART:-charts/api}"

# 1) Initialize the local-only root, then apply it against the emulator.
terraform -chdir=terraform/environments/floci init -backend=false -input=false
FLOCI_TOKEN="$("$FLOCI_DIR/awslocal" eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token')"
export FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true
export TF_VAR_floci_k8s_token="$FLOCI_TOKEN"
terraform -chdir=terraform/environments/floci apply \
  -target=module.eks \
  -target=module.lbc \
  -target=aws_iam_role.lbc \
  -target=aws_iam_role_policy.lbc \
  -target=module.lbc.aws_iam_role.this \
  -target=module.lbc.aws_iam_role_policy.this \
  -auto-approve
terraform -chdir=terraform/environments/floci apply -auto-approve

# 2) Point kubectl at the emulated cluster (static-token kubeconfig).
umask 077
FLOCI_EP="$("$FLOCI_DIR/awslocal" eks describe-cluster --name eks-api-floci --profile floci --output text --query 'cluster.endpoint')"
FLOCI_TOKEN="$("$FLOCI_DIR/awslocal" eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token')"
printf 'apiVersion: v1\nkind: Config\nclusters:\n- cluster:\n    server: %s\n    insecure-skip-tls-verify: true\n  name: floci\ncontexts:\n- context: {cluster: floci, user: floci}\n  name: floci\ncurrent-context: floci\nusers:\n- name: floci\n  user: {token: %s}\n' "$FLOCI_EP" "$FLOCI_TOKEN" > "$FLOCI_KC"
echo "floci-validate: kubeconfig -> $FLOCI_KC ($FLOCI_EP)"

# 3) Check chart server-side, install it to verify live resource creation, then
#    client-validate each per-environment ArgoCD bootstrap set.
export KUBECONFIG="$FLOCI_KC"
helm template api "$CHART" -f "$CHART/values-dev.yaml" | kubectl apply --dry-run=server -f -
helm upgrade --install api "$CHART" --namespace api-floci --create-namespace -f "$CHART/values-dev.yaml"
kubectl -n api-floci get secret api-db-credentials >/dev/null
kubectl -n api-floci get deployment/api service/api ingress/api >/dev/null
kubectl -n api-floci wait --for=condition=PodScheduled pod -l app.kubernetes.io/instance=api --timeout=120s

for env in dev staging prod; do
  kubectl apply --dry-run=client --validate=false \
    -f "apps/argocd/root-$env.yaml" \
    -f "apps/argocd/environments/$env"
done
echo "floci-validate: resources created; ArgoCD manifests parsed (external AWS data plane unavailable)"
