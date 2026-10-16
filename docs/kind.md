# Kind — local API and PostgreSQL end-to-end validation

Kind runs the production API container and a real PostgreSQL container in an
isolated local Kubernetes cluster. The make kind-e2e target waits for both
workloads, forwards the API ClusterIP Service to localhost, then checks
health, readiness, and HTTP CRUD against PostgreSQL.

## Run

Prerequisites: Docker, Kind, kubectl, Helm, curl, and Python 3. Docker must be
running. The script builds the API image from apps/api/Dockerfile; Docker pulls
the Kind node and postgres:16-alpine images if they are not cached.

    make kind-e2e

Override the Kind binary or local HTTP port if needed:

    make kind-e2e KIND=/path/to/kind
    KIND_E2E_PORT=18080 make kind-e2e

The script creates a unique cluster and kubeconfig, uses a test-only database
password, and deletes only that cluster and its temporary kubeconfig on exit.
It also removes the unique API image tag it built. Docker may keep downloaded
base images cached.

## What this proves

- The built API image starts in Kubernetes and becomes ready after connecting
  to PostgreSQL.
- The chart's ClusterIP Service routes requests to the API pod.
- /healthz and /readyz return success.
- Create, list, get, update, delete, and get-after-delete exercise the API and
  persist through the PostgreSQL data path.

## Boundary

Kind is Kubernetes, not AWS. This check does not emulate AWS EKS, ECR, RDS,
ALB or the AWS Load Balancer Controller, IAM, VPC routing, security groups, or
production TLS. The local request uses kubectl port-forward to reach the
Kubernetes Service; it does not test ALB ingress behavior.

Use both validators:

| Check | Validates |
| --- | --- |
| make floci-validate | Terraform and AWS resource shape, chart installation, and ArgoCD manifest parsing |
| make kind-e2e | Live API-to-PostgreSQL traffic and CRUD in Kubernetes |
| docs/runbook-aws.md | Real AWS networking, ECR pulls, RDS, ALB, and production deployment path |
