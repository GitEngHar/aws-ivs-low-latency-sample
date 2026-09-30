# todo 録画用のバケット
resource "aws_s3_bucket" "ivs_low_latency_recording_live" {
  bucket        = "ivs-low-latency-recording-live"
  force_destroy = true
  tags = {
    Name = "ivs-low-latency-recording-live"
  }
}


resource "aws_s3_bucket_lifecycle_configuration" "ivs_low_latency_recording_live_lifecycle" {
  bucket = aws_s3_bucket.ivs_low_latency_recording_live.bucket
  rule {
    id     = "480p-deep-archive"
    status = "Enabled"
    filter {
      tag {
        key   = "resolution"
        value = "480"
      }
    }
    transition {
      days          = 1
      storage_class = "DEEP_ARCHIVE"
    }
  }
  rule {
    id     = "480p-deep-delete"
    status = "Enabled"
    filter {
      tag {
        key   = "resolution"
        value = "480"
      }
    }
    expiration {
      days = 2
    }
  }
  rule {
    id     = "1080-delete-movie"
    status = "Enabled"
    filter {
      tag {
        key   = "resolution"
        value = "1080"
      }
    }
    expiration {
      days = 1
    }
  }
  rule {
    id     = "delete-thumbnail"
    status = "Enabled"
    filter {
      tag {
        key   = "resolution"
        value = "thumbnail"
      }
    }
    expiration {
      days = 1
    }
  }
}


# IVS writes <prefix>/events/recording-ended.json when a recording finishes.
# Invoke the tagging lambda on that PUT.
resource "aws_s3_bucket_notification" "ivs_low_latency_recording_live" {
  bucket = aws_s3_bucket.ivs_low_latency_recording_live.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.resolution_tag_add.arn
    events              = ["s3:ObjectCreated:Put"]
    filter_suffix       = "events/recording-ended.json"
  }

  depends_on = [aws_lambda_permission.resolution_tag_add_s3]
}
