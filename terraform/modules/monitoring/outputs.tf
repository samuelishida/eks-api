output "sns_topic_arn" {
  description = "ARN of the alerts SNS topic."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_arns" {
  description = "ARNs of all metric alarms."
  value = [
    aws_cloudwatch_metric_alarm.alb_5xx.arn,
    aws_cloudwatch_metric_alarm.rds_cpu.arn,
    aws_cloudwatch_metric_alarm.rds_free_storage.arn,
    aws_cloudwatch_metric_alarm.node_count.arn,
    aws_cloudwatch_metric_alarm.control_plane_errors.arn,
  ]
}
