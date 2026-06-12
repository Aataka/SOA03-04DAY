# myDashboard（タスク3再現）: 必要なメトリクスだけのカスタムビューを IaC 化。
# 検証対象外（スクショ用）。

resource "aws_cloudwatch_dashboard" "my_dashboard" {
  dashboard_name = "myDashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "AppServer memory"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.app_server.id],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "AppServer network activity"
          region  = var.region
          view    = "timeSeries"
          stacked = true
          stat    = "Average"
          period  = 300
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.app_server.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.app_server.id],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "lambda-canary health"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.canary.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.canary.function_name],
          ]
        }
      },
    ]
  })
}
