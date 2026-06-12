# --- Lambda Canary（タスク7再現） ---------------------------------------------

data "archive_file" "canary" {
  type        = "zip"
  source_file = "${path.module}/lambda/canary.py"
  output_path = "${path.module}/lambda/canary.zip"
}

resource "aws_iam_role" "canary" {
  name_prefix = "soa03-4day-canary-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "canary_logs" {
  role       = aws_iam_role.canary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 保持期間は必ず明示（コンソール既定の「失効しない」はストレージ課金が無限増大）
resource "aws_cloudwatch_log_group" "canary" {
  name              = "/aws/lambda/lambda-canary"
  retention_in_days = 30
}

resource "aws_lambda_function" "canary" {
  function_name = "lambda-canary"
  role          = aws_iam_role.canary.arn
  runtime       = "python3.12"
  handler       = "canary.handler"
  timeout       = 15

  filename         = data.archive_file.canary.output_path
  source_code_hash = data.archive_file.canary.output_base64sha256

  environment {
    variables = {
      site     = var.canary_site
      expected = var.canary_expected
    }
  }

  depends_on = [aws_cloudwatch_log_group.canary]
}

# --- EventBridge: rate(1 minute) で canary を定期実行 -------------------------

resource "aws_cloudwatch_event_rule" "canary_schedule" {
  name                = "CheckWebsiteScheduledEvent"
  description         = "CheckWebsiteScheduledEvent trigger"
  schedule_expression = "rate(1 minute)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "canary" {
  rule = aws_cloudwatch_event_rule.canary_schedule.name
  arn  = aws_lambda_function.canary.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.canary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.canary_schedule.arn
}
