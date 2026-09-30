# todo [動画削除用 lambda] object定期削除用lambda。画像は1年後。1080p動画は2週間後に削除。480pはタグ付けを1回だけ実施して何もしない
# サムネイルは5分で削除
# 動画の480p/1080p動画に対してタグ付をする
# 1080p動画は3分で削除
# 480p動画のDeepArchive動画は10分で削除

# Go binary is built outside of Terraform (see README):
#   cd lambda && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o build/bootstrap .
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/build/bootstrap"
  output_path = "${path.module}/lambda/build/lambda.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# resolution_tag_add: IVS録画終了 (events/recording-ended.json のPUT) を契機に
# 録画オブジェクトへ resolution タグを付与する
# ---------------------------------------------------------------------------
resource "aws_iam_role" "resolution_tag_add" {
  name               = "${var.name_prefix}-resolution-tag-add"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "resolution_tag_add_basic" {
  role       = aws_iam_role.resolution_tag_add.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "resolution_tag_add_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ivs_low_latency_recording_live.arn]
  }
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = ["${aws_s3_bucket.ivs_low_latency_recording_live.arn}/*"]
  }
}

resource "aws_iam_role_policy" "resolution_tag_add_s3" {
  name   = "s3-recording-tagging"
  role   = aws_iam_role.resolution_tag_add.id
  policy = data.aws_iam_policy_document.resolution_tag_add_s3.json
}

resource "aws_cloudwatch_log_group" "resolution_tag_add" {
  name              = "/aws/lambda/${var.name_prefix}-resolution-tag-add"
  retention_in_days = 1
}

resource "aws_lambda_function" "resolution_tag_add" {
  function_name    = "${var.name_prefix}-resolution-tag-add"
  role             = aws_iam_role.resolution_tag_add.arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "bootstrap"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      BATCH_NAME = "resolution_tag_add"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.resolution_tag_add_basic,
    aws_cloudwatch_log_group.resolution_tag_add,
  ]
}

resource "aws_lambda_permission" "resolution_tag_add_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.resolution_tag_add.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.ivs_low_latency_recording_live.arn
  source_account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# ivs_event_route: EventBridge の IVS Stream State / Health Change を契機に
# channel 情報 (tags含む) を取得してイベント種別ごとに標準出力する
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ivs_event_route" {
  name               = "${var.name_prefix}-ivs-event-route"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ivs_event_route_basic" {
  role       = aws_iam_role.ivs_event_route.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "ivs_event_route_ivs" {
  statement {
    actions   = ["ivs:GetChannel"]
    resources = ["arn:aws:ivs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:channel/*"]
  }
}

resource "aws_iam_role_policy" "ivs_event_route_ivs" {
  name   = "ivs-get-channel"
  role   = aws_iam_role.ivs_event_route.id
  policy = data.aws_iam_policy_document.ivs_event_route_ivs.json
}

resource "aws_cloudwatch_log_group" "ivs_event_route" {
  name              = "/aws/lambda/${var.name_prefix}-ivs-event-route"
  retention_in_days = 1
}

resource "aws_lambda_function" "ivs_event_route" {
  function_name    = "${var.name_prefix}-ivs-event-route"
  role             = aws_iam_role.ivs_event_route.arn
  runtime          = "provided.al2023"
  architectures    = ["arm64"]
  handler          = "bootstrap"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      BATCH_NAME = "ivs_event_route"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ivs_event_route_basic,
    aws_cloudwatch_log_group.ivs_event_route,
  ]
}
