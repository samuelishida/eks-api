#!/usr/bin/env sh
# floci-validate — terraform apply (floci) + helm/kubectl dry-runs + shape checks.
# Invoked from the repo root by `make floci-validate`.
set -eu

FLOCI_DIR="${FLOCI_DIR:-../aws-tools/local-emulator}"
FLOCI_KC="${FLOCI_KC:-/tmp/floci-eks-api-kubeconfig}"
CHART="${CHART:-charts/api}"

# 1) Apply the floci environment (emulated AWS via the [floci] profile).
FLOCI_TOKEN="$("$FLOCI_DIR/awslocal" eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token')"
export FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true
export TF_VAR_floci_k8s_token="$FLOCI_TOKEN"
terraform -chdir=terraform/environments/floci apply -auto-approve

# 2) Point kubectl at the emulated cluster (static-token kubeconfig).
FLOCI_EP="$("$FLOCI_DIR/awslocal" eks describe-cluster --name eks-api-floci --profile floci --output text --query 'cluster.endpoint')"
FLOCI_TOKEN="$("$FLOCI_DIR/awslocal" eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token')"
printf 'apiVersion: v1\nkind: Config\nclusters:\n- cluster:\n    server: %s\n    insecure-skip-tls-verify: true\n  name: floci\ncontexts:\n- context: {cluster: floci, user: floci}\n  name: floci\ncurrent-context: floci\nusers:\n- name: floci\n  user: {token: %s}\n' "$FLOCI_EP" "$FLOCI_TOKEN" > "$FLOCI_KC"
echo "floci-validate: kubeconfig -> $FLOCI_KC ($FLOCI_EP)"

# 3) Shape checks: the chart renders and applies cleanly; ArgoCD manifests parse.
export KUBECONFIG="$FLOCI_KC"
helm template api "$CHART" -f "$CHART/values-dev.yaml" | kubectl apply --dry-run=server -f -
kubectl apply --dry-run=client --validate=false -f apps/argocd/
echo "floci-validate: shape checks complete (CRDs needed for full ArgoCD dry-run: see docs/floci.md)"
