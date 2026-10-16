# GitHub Actions

Configure repository variables `AWS_ACCOUNT_ID`, `AWS_REGION`, and
`AWS_BUILD_ROLE_ARN`. The build role uses OIDC and needs ECR push access to
`eks-api-api-{dev,staging,prod}`. Workflow only grants `id-token: write` to the
image-push job; pull-request tests get read-only repository access.

Successful builds on `main` push one immutable commit SHA to all three ECR
repositories. The deploy workflow opens a PR for the dev values file. Promote
the same SHA to staging/prod with reviewed values-file changes.

Terraform workflow runs init without backend, validate, and fmt checks only. It
does not plan or apply against AWS state. Provenance workflow enforces the
repository's merge-history policy.
