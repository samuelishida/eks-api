# eks-api — thin wrappers over terraform / helm / go / floci.
# Usage: make <target> [ENV=dev|staging|prod|floci]

ENV      ?= dev
TF_DIR   := terraform/environments/$(ENV)
CHART    := charts/api
API_DIR  := apps/api
GO       ?= go

.PHONY: help tf-init tf-plan tf-apply tf-destroy tf-validate \
        helm-lint helm-template api-test api-build api-run \
        floci-up floci-down floci-validate

help: ## List targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

tf-init: ## terraform init for ENV (default dev)
	terraform -chdir=$(TF_DIR) init

tf-plan: ## terraform plan for ENV
	terraform -chdir=$(TF_DIR) plan

tf-apply: ## terraform apply for ENV
	terraform -chdir=$(TF_DIR) apply -auto-approve

tf-destroy: ## terraform destroy for ENV
	terraform -chdir=$(TF_DIR) destroy -auto-approve

tf-validate: ## terraform validate for ENV
	terraform -chdir=$(TF_DIR) validate

helm-lint: ## helm lint charts/api against each env values file
	helm lint $(CHART) -f $(CHART)/values-dev.yaml
	helm lint $(CHART) -f $(CHART)/values-staging.yaml
	helm lint $(CHART) -f $(CHART)/values-prod.yaml

helm-template: ## helm template charts/api (dev values by default)
	helm template api $(CHART) -f $(CHART)/values-dev.yaml

api-test: ## go vet + go test for the API
	cd $(API_DIR) && $(GO) vet ./... && $(GO) test ./...

api-build: ## docker build the API image
	docker build -t eks-api-api:$(shell git rev-parse --short HEAD 2>/dev/null || echo dev) $(API_DIR)

api-run: ## run the API locally (needs a Postgres; see apps/api/README)
	cd $(API_DIR) && $(GO) run ./cmd/api

floci-up: ## start the Floci emulator (aws-tools/local-emulator)
	@cd ../aws-tools/local-emulator && docker compose up -d

floci-down: ## stop the Floci emulator
	@cd ../aws-tools/local-emulator && docker compose down

FLOCI_DIR  := ../aws-tools/local-emulator
FLOCI_KC   := /tmp/floci-eks-api-kubeconfig

floci-validate: ## terraform apply (floci) + helm/kubectl dry-runs + shape checks
	@export FLOCI_SERVICES_EKS_DEFAULT_STORAGE_CLASS=true; \
	FLOCI_TOKEN=$$($(FLOCI_DIR)/awslocal eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token'); \
	export TF_VAR_floci_k8s_token="$$FLOCI_TOKEN"; \
	terraform -chdir=terraform/environments/floci apply -auto-approve
	@FLOCI_EP=$$($(FLOCI_DIR)/awslocal eks describe-cluster --name eks-api-floci --profile floci --output text --query 'cluster.endpoint'); \
	FLOCI_TOKEN=$$($(FLOCI_DIR)/awslocal eks get-token --cluster-name eks-api-floci --profile floci --output text --query 'status.token'); \
	printf 'apiVersion: v1\nkind: Config\nclusters:\n- cluster:\n    server: %s\n    insecure-skip-tls-verify: true\n  name: floci\ncontexts:\n- context: {cluster: floci, user: floci}\n  name: floci\ncurrent-context: floci\nusers:\n- name: floci\n  user: {token: %s}\n' "$$FLOCI_EP" "$$FLOCI_TOKEN" > $(FLOCI_KC); \
	echo "floci-validate: kubeconfig -> $(FLOCI_KC) ($$FLOCI_EP)"
	@export KUBECONFIG=$(FLOCI_KC); \
	helm template api $(CHART) -f $(CHART)/values-dev.yaml | kubectl apply --dry-run=server -f -
	@kubectl apply --dry-run=client --validate=false -f apps/argocd/
	@echo "floci-validate: shape checks complete (CRDs needed for full ArgoCD dry-run: see docs/floci.md)"
