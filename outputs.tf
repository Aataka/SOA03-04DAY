output "instance_id" {
  value = aws_instance.app_server.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.sysops_team_pager.arn
}

output "canary_function_name" {
  value = aws_lambda_function.canary.function_name
}

output "canary_rule_name" {
  value = aws_cloudwatch_event_rule.canary_schedule.name
}

output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.system_check.alarm_name,
    aws_cloudwatch_metric_alarm.instance_check_reboot.alarm_name,
    aws_cloudwatch_metric_alarm.mem_high.alarm_name,
    aws_cloudwatch_metric_alarm.canary_errors_60s.alarm_name,
    aws_cloudwatch_metric_alarm.canary_errors_300s.alarm_name,
    aws_cloudwatch_metric_alarm.canary_alive.alarm_name,
  ]
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.my_dashboard.dashboard_name}"
}
