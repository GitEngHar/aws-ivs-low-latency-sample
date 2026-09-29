# todo 録画用のバケット
resource "aws_s3_bucket" "ivs_low_latency_recording_live" {
  bucket = "ivs_low_latency_recording_live"
  force_destroy = true
  tags = {
    Name = "ivs_low_latency_recording_live"
  }
}

# todo オブジェクトライフサイクルポリシー
# 480p動画は1日でDeepArchiveへ移動
resource "aws_s3_bucket_lifecycle_configuration" "ivs_low_latency_recording_live_lifecycle" {
  bucket = aws_s3_bucket.ivs_low_latency_recording_live.bucket
  rule {
    id = "deep-archive-10-min"
    status = "Enabled"
    filter {
      tag {
        key = "resolution"
        value = "480"
      }
    }
    transition {
      days = 1
      storage_class = "DEEP_ARCHIVE"
    }
  }
}
