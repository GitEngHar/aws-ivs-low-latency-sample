# Captures AWS IVS "Stream State Change" (stream start/end) and
# "Stream Health Change" (starvation start/end) events emitted by every IVS
# channel in the account. Each rule writes the raw event to CloudWatch Logs
# for inspection and also invokes the ivs_event_route lambda (lambda.tf).
resource "aws_cloudwatch_log_group" "ivs_stream_state_change" {
  name              = "/aws/events/${var.name_prefix}/ivs-stream-state-change"
  retention_in_days = 1
}

resource "aws_cloudwatch_event_rule" "ivs_stream_state_change" {
  name        = "${var.name_prefix}-ivs-stream-state-change"
  description = "Matches AWS IVS Stream State Change events for all channels in the account"

  event_pattern = jsonencode({
    source      = ["aws.ivs"]
    detail-type = ["IVS Stream State Change"]
  })
}
resource "aws_cloudwatch_event_rule" "ivs_stream_state_not_health" {
  name        = "${var.name_prefix}-ivs-stream-not-health"
  description = "Matches AWS IVS Stream State Change events for all channels in the account"

  event_pattern = jsonencode({
    source      = ["aws.ivs"]
    detail-type = ["IVS Stream Health Change"],
    "detail" : {
      "event_name" : [
        "Starvation Start",
      ]
    }
  })
}

resource "aws_cloudwatch_event_rule" "ivs_stream_state_be_health" {
  name        = "${var.name_prefix}-ivs-stream-state-be-health"
  description = "Matches AWS IVS Stream State Change events for all channels in the account"

  event_pattern = jsonencode({
    source      = ["aws.ivs"]
    detail-type = ["IVS Stream Health Change"],
    "detail" : {
      "event_name" : [
        "Starvation End",
      ]
    }
  })
}


resource "aws_cloudwatch_log_group" "ivs_stream_health_change" {
  name              = "/aws/events/${var.name_prefix}/ivs-stream-health-change"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_resource_policy" "ivs_stream_health_change" {
  policy_name = "${var.name_prefix}-ivs-stream-health-change"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeToWriteLogs"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.ivs_stream_health_change.arn}:*"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_cloudwatch_event_rule.ivs_stream_state_not_health.arn,
              aws_cloudwatch_event_rule.ivs_stream_state_be_health.arn,
            ]
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "ivs_stream_state_not_health_logs" {
  rule = aws_cloudwatch_event_rule.ivs_stream_state_not_health.name
  arn  = aws_cloudwatch_log_group.ivs_stream_health_change.arn
}

resource "aws_cloudwatch_event_target" "ivs_stream_state_be_health_logs" {
  rule = aws_cloudwatch_event_rule.ivs_stream_state_be_health.name
  arn  = aws_cloudwatch_log_group.ivs_stream_health_change.arn
}

resource "aws_cloudwatch_log_resource_policy" "ivs_stream_state_change" {
  policy_name = "${var.name_prefix}-ivs-stream-state-change"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeToWriteLogs"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.ivs_stream_state_change.arn}:*"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.ivs_stream_state_change.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "ivs_stream_state_change_logs" {
  rule = aws_cloudwatch_event_rule.ivs_stream_state_change.name
  arn  = aws_cloudwatch_log_group.ivs_stream_state_change.arn
}

# ---------------------------------------------------------------------------
# ivs_event_route lambda targets
# ---------------------------------------------------------------------------
locals {
  ivs_event_route_rules = {
    stream_state_change = aws_cloudwatch_event_rule.ivs_stream_state_change
    stream_not_health   = aws_cloudwatch_event_rule.ivs_stream_state_not_health
    stream_be_health    = aws_cloudwatch_event_rule.ivs_stream_state_be_health
  }
}

resource "aws_lambda_permission" "ivs_event_route_eventbridge" {
  for_each = local.ivs_event_route_rules

  statement_id  = "AllowEventBridgeInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ivs_event_route.function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.arn
}

resource "aws_cloudwatch_event_target" "ivs_event_route_lambda" {
  for_each = local.ivs_event_route_rules

  rule = each.value.name
  arn  = aws_lambda_function.ivs_event_route.arn

  depends_on = [aws_lambda_permission.ivs_event_route_eventbridge]
}
