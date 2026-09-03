# Captures AWS IVS "Stream State Change" events (stream start/end) emitted
# by every IVS channel in the account and writes them to CloudWatch Logs so
# they can be inspected locally during development. The target is
# intentionally minimal (logs only) — swap aws_cloudwatch_event_target for
# SNS/Lambda/SQS once a real consumer (e.g. a live-control-plane webhook) is
# ready, without touching the rule's event pattern.

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
