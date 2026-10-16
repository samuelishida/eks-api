# Monitoring & Alerts (Inc 8)

Alerting is implemented with a small Terraform module (terraform/modules/monitoring/)
wired into the dev, staging, and prod environments. Floci checks AWS resource shape;
Kind checks API-to-PostgreSQL traffic. Current local checks do not validate CloudWatch
metrics, alarm delivery, or SNS notifications; verify those in real AWS.

## What is alerted

All alarms publish to a single per-environment SNS topic
(`<name>-<env>-alerts`). An optional email subscription is created only when
`sns_email` is set (it is `""` in all envs today, so no subscription is created).

| Alarm | Namespace / Metric | Statistic | Period | Comparison | Eval periods |
|---|---|---|---|---|---|
| `alb_5xx` | `AWS/ApplicationELB` / `HTTPCode_Target_5XX_Count` | Sum | 60s | >= threshold | 1 |
| `alb_unhealthy_targets` | `AWS/ApplicationELB` / `UnHealthyHostCount` | Maximum | 60s | >= 1 | 2 |
| `rds_cpu` | `AWS/RDS` / `CPUUtilization` | Average | 300s | >= threshold | 2 |
| `rds_free_storage` | `AWS/RDS` / `FreeStorageSpace` | Average | 300s | < threshold | 1 |
| `node_count` | `AWS/EC2` / `GroupInServiceInstances` | Sum | 300s | < threshold | 1 |
| `control_plane_errors` | `AWS/EKS` / `apiserver_request_total_5XX` | Sum | 300s | >= threshold | 1 |

### Thresholds per environment

| Threshold | dev | staging | prod |
|---|---|---|---|
| `alb_5xx_threshold` (5xx / 60s) | 20 | 10 | 5 |
| `rds_cpu_threshold` (%) | 90 | 85 | 70 |
| `rds_free_storage_threshold` (bytes) | 5 GiB | 5 GiB | 10 GiB |
| `node_count_threshold` (min in-service) | 1 | 1 | 2 |
| `cp_5xx_threshold` (requests / 5m) | 5 | 5 | 5 |

Dimensions:
- `alb_*` → CloudWatch suffixes, e.g. `LoadBalancer = app/name/id`, `TargetGroup = targetgroup/name/id`
- `rds_*` → `DBInstanceIdentifier = module.rds.identifier`
- `node_count` → `AutoScalingGroupName = module.eks.asg_names["node"].asg_names[0]`
- `control_plane_errors` → `ClusterName = module.eks.cluster_name`

### ALB dimensions: fill after first sync

The ALB and target group are created **at runtime** by the AWS Load Balancer
Controller (Inc 6), so those alarm resources stay disabled until dimensions are
known. After first sync, get each resource ARN with `aws elbv2 describe-*`, take
the suffix after `loadbalancer/` or `targetgroup/`, and set `alb_name` and
`target_group_name` in the environment's `monitoring.tf`.

## Where logs land

- **EKS control plane** → CloudWatch Logs group
  `/aws/eks/<cluster-name>/cluster` (enabled via the `logging` map var on the
  EKS module: `api,audit,auth,controllerManager,scheduler`).
- **Node and container logs** are not shipped by this Terraform configuration.
  Add and configure the CloudWatch Observability add-on or another log collector
  before relying on centralized worker/container logs.

> **Cost note:** control-plane logging is billed per GB-ingested and retained
> CloudWatch Logs retention. EKS module defaults retention to **90 days** in all
> environments; override if dev should retain less.

## Optional: Prometheus / Alertmanager / Grafana

For in-cluster metrics beyond the CloudWatch alarms above, install
`kube-prometheus-stack` (which bundles Prometheus, Alertmanager, and Grafana):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values.yaml
```

`values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 15d

grafana:
  adminPassword: CHANGE_ME

alertmanager:
  enabled: true
```

- `prometheus.prometheusSpec.retention: 15d` — bounded Prometheus retention.
- `grafana.adminPassword` — replace the `CHANGE_ME` placeholder with a real
  password (or manage it via a secret / external secret manager).
- `alertmanager.enabled: true` — turns on Alertmanager; wire its routing to the
  same SNS topic (or a webhook) as the CloudWatch alarms.
