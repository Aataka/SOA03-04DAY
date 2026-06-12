# --- ラボ再現: StatusCheckFailed_System（通知のみ） --------------------------
# set-alarm-state による通知テストと「自動OK復帰までの秒数」実測に使う（仮説G）。

resource "aws_cloudwatch_metric_alarm" "system_check" {
  alarm_name        = "AppServerSystemsCheckAlarm"
  alarm_description = "EC2 System Reachability check failed. Network packets are likely not reaching the instance. See runbook."

  namespace   = "AWS/EC2"
  metric_name = "StatusCheckFailed_System"
  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [aws_sns_topic.sysops_team_pager.arn]
  ok_actions    = [aws_sns_topic.sysops_team_pager.arn] # 復旧も通知
}

# --- 仮説G: set-alarm-state は EC2 アクション（reboot）も発火させるか ---------
# StatusCheckFailed_Instance >= 1 で「インスタンス再起動」を自動修復として設定。
# set-alarm-state でこのアラームを ALARM にすると、通知テストのつもりが
# 本物の reboot が走ることを実証する。

resource "aws_cloudwatch_metric_alarm" "instance_check_reboot" {
  alarm_name        = "AppServerInstanceRebootAlarm"
  alarm_description = "EC2 Instance Reachability check failed. Auto-remediation: reboot the instance."

  namespace   = "AWS/EC2"
  metric_name = "StatusCheckFailed_Instance"
  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [
    "arn:aws:automate:${var.region}:ec2:reboot",
    aws_sns_topic.sysops_team_pager.arn,
  ]
  ok_actions = [aws_sns_topic.sysops_team_pager.arn]
}

# --- 仮説H: メモリ枯渇は CloudWatch Agent でしか見えない ----------------------
# 標準メトリクス（CPUUtilization 等）はメモリ負荷に無反応のはず。
# CWAgent の mem_used_percent にアラームを張り、stress-ng で実測する。

resource "aws_cloudwatch_metric_alarm" "mem_high" {
  alarm_name        = "AppServerMemHighAlarm"
  alarm_description = "Memory usage exceeded ${var.mem_alarm_threshold}% (CloudWatch Agent mem_used_percent)."

  namespace   = "CWAgent"
  metric_name = "mem_used_percent"
  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.mem_alarm_threshold
  comparison_operator = "GreaterThanThreshold"

  alarm_actions = [aws_sns_topic.sysops_team_pager.arn]
  ok_actions    = [aws_sns_topic.sysops_team_pager.arn]
}

# --- 仮説J: 同じ Errors >= 1 でも period 60s と 300s で検知遅延がどう違うか ---

resource "aws_cloudwatch_metric_alarm" "canary_errors_60s" {
  alarm_name        = "lambda-canary-errors-60s"
  alarm_description = "Lambda Canary did not receive the expected response from the website (period=60s)."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.canary.function_name
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [aws_sns_topic.sysops_team_pager.arn]
  ok_actions    = [aws_sns_topic.sysops_team_pager.arn]
}

resource "aws_cloudwatch_metric_alarm" "canary_errors_300s" {
  alarm_name        = "lambda-canary-errors-300s"
  alarm_description = "Lambda Canary did not receive the expected response from the website (period=300s, lab default)."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.canary.function_name
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [aws_sns_topic.sysops_team_pager.arn]
  ok_actions    = [aws_sns_topic.sysops_team_pager.arn]
}

# --- 仮説I: カナリアの死は誰が見るのか（生存監視） ----------------------------
# EventBridge ルールが無効化/誤削除されると canary は黙って止まり、Errors は
# 「欠落」する（Errors アラームでは検知不能）。Invocations < 1 を
# treat_missing_data = breaching で監視して「監視の監視」を成立させる。

resource "aws_cloudwatch_metric_alarm" "canary_alive" {
  alarm_name        = "lambda-canary-alive"
  alarm_description = "Lambda Canary stopped being invoked (scheduler down / rule disabled). Watch the watcher."

  namespace   = "AWS/Lambda"
  metric_name = "Invocations"
  dimensions = {
    FunctionName = aws_lambda_function.canary.function_name
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching" # 欠落 = canary 停止とみなす

  alarm_actions = [aws_sns_topic.sysops_team_pager.arn]
  ok_actions    = [aws_sns_topic.sysops_team_pager.arn]
}
