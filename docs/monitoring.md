# Monitoring & Alerts (Inc 8)

Alerting is implemented with a small Terraform module (`terraform/modules/monitoring/`)
wired into the `dev`, `staging`, and `prod` environments. `floci` is shape-only and has
no monitoring wiring.

## What is alerted

All alarms publish to a single per-environment SNS topic
(`<name>-<env>-alerts`). An optional email subscription is created only when
`sns_email` is set (it is `""` in all envs today, so no subscription is created).

| Alarm | Namespace / Metric | Statistic | Period | Comparison | Eval periods |
|---|---|---|---|---|---|
| `alb_5xx` | `AWS/ApplicationELB` / `HTTPCode_Target_5XX_Count` | Sum | 60s | >= threshold | 1 |
| `rds_cpu` | `AWS/RDS` / `CPUUtilization` | Average | 300s | >= threshold | 2 |
| `rds_free_storage` | `AWS/RDS` / `FreeStorageSpace` | Average | 300s | < threshold | 1 |
| `node_count` | `AWS/EC2` / `GroupInServiceInstances` | Sum | 300s | < threshold | 1 |
| `control_plane_errors` | `AWS/EKS` / `ControlPlaneErrorRate` | Average | 300s | >= threshold | 1 |

### Thresholds per environment

| Threshold | dev | staging | prod |
|---|---|---|---|
| `alb_5xx_threshold` (5xx / 60s) | 20 | 10 | 5 |
| `rds_cpu_threshold` (%) | 90 | 85 | 70 |
| `rds_free_storage_threshold` (bytes) | 100 GiB | 100 GiB | 50 GiB |
| `node_count_threshold` (min in-service) | 1 | 1 | 2 |
| `cp_error_threshold` (error rate) | 0.01 | 0.01 | 0.01 |

Dimensions:
- `alb_5xx` → `LoadBalancer = alb_name`, `TargetGroup = target_group_arn`
- `rds_*` → `DBInstanceIdentifier = module.rds.identifier`
- `node_count` → `AutoScalingGroupName = module.eks.asg_names["node"].asg_names[0]`
- `control_plane_errors` → `ClusterName = module.eks.cluster_name`

### ALB dimensions: fill after first sync

The ALB and its target group are created **at runtime** by the AWS Load Balancer
Controller (Inc 6), so their names are not knowable at `terraform apply` time. The
module therefore takes `alb_name` and `target_group_arn` as variables (default `""`).
After the first sync, look up the ALB name and target-group ARN (e.g.
`aws elbv2 describe-load-balancers` / `describe-target-groups`) and set them in the
env's `monitoring.tf` so the 5xx alarm has real dimensions.

## Where logs land

- **EKS control plane** → CloudWatch Logs group
  `aws/eks/<cluster-name>/control-plane` (enabled via the `logging` map var on the
  EKS module: `api,audit,auth,controllerManager,scheduler`).
- **Node group / worker** → CloudWatch Logs via the `awslogs` agent on the managed
  node group (kubelet, systemd, container logs under `/var/log/containers` etc.).

> **Cost note:** control-plane logging is billed per GB-ingested and retained
> CloudWatch Logs retention. Keep retention bounded: **30 days in dev**, **90 days
> in prod** (set on the `aws/eks/.../control-plane` log group).

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
