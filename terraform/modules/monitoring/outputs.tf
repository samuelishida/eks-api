output "sns_topic_arn" {
  description = "ARN of the alerts SNS topic."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_arns" {
  description = "ARNs of all metric alarms."
  value = [
    for alarm in concat(
      aws_cloudwatch_metric_alarm.alb_5xx,
      aws_cloudwatch_metric_alarm.alb_unhealthy_targets,
      [
        aws_cloudwatch_metric_alarm.rds_cpu,
        aws_cloudwatch_metric_alarm.rds_free_storage,
        aws_cloudwatch_metric_alarm.node_count,
        aws_cloudwatch_metric_alarm.control_plane_errors,
      ],
    ) : alarm.arn
  ]
}
