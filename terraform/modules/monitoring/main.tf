# Monitoring — SNS alerting + CloudWatch metric alarms (Inc 8).
#
# The ALB is created at runtime by the AWS Load Balancer Controller (Inc 6), so
# its name and the target-group ARN are NOT knowable at apply time. Both are
# passed in as variables (defaults "") — fill them in after the first sync so
# the ALB 5xx alarm has real dimensions.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-${var.env}-alerts"

  tags = {
    Name = "${var.name}-${var.env}-alerts"
    Env  = var.env
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.sns_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# --- ALB 5xx (target) ---------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_name != "" && var.target_group_name != "" ? 1 : 0

  alarm_name          = "${var.name}-${var.env}-alb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_name
    TargetGroup  = var.target_group_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${var.env}-alb-5xx"
    Env  = var.env
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  count = var.alb_name != "" && var.target_group_name != "" ? 1 : 0

  alarm_name          = "${var.name}-${var.env}-alb-unhealthy-targets"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_name
    TargetGroup  = var.target_group_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${var.env}-alb-unhealthy-targets"
    Env  = var.env
  }
}

# --- RDS CPU ------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-${var.env}-rds-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${var.env}-rds-cpu"
    Env  = var.env
  }
}

# --- RDS free storage ---------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.name}-${var.env}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_free_storage_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${var.env}-rds-free-storage"
    Env  = var.env
  }
}

# --- Node group in-service count ---------------------------------------------
resource "aws_cloudwatch_metric_alarm" "node_count" {
  alarm_name          = "${var.name}-${var.env}-node-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Sum"
  threshold           = var.node_count_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${var.env}-node-count"
    Env  = var.env
  }
}

# --- EKS control-plane API-server 5xx count ----------------------------------
resource "aws_cloudwatch_metric_alarm" "control_plane_errors" {
  alarm_name          = "${var.name}-${var.env}-cp-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "apiserver_request_total_5XX"
  namespace           = "AWS/EKS"
  period              = 300
  statistic           = "Sum"
  threshold           = var.cp_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name}-${var.env}-cp-errors"
    Env  = var.env
  }
}
