# todo 録画用のバケット
resource "aws_s3_bucket" "ivs_low_latency_recording_live" {
  bucket = "ivs_low_latency_recording_live"
  force_destroy = true
  tags = {
    Name = "ivs_low_latency_recording_live"
  }
}


resource "aws_s3_bucket_lifecycle_configuration" "ivs_low_latency_recording_live_lifecycle" {
  bucket = aws_s3_bucket.ivs_low_latency_recording_live.bucket
  rule {
    id = "480p-deep-archive"
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
  rule {
    id = "1080-delete-movie"
    status = "Enabled"
    filter {
      tag {
        key = "resolution"
        value = "1080"
      }
    }
    expiration {
      days = 1
    }
  }
  rule {
    id = "delete-thumbnail"
    status = "Enabled"
    filter {
      tag {
        key = "resolution"
        value = "thumbnail"
      }
    }
    expiration {
      days = 1
    }
  }
}

