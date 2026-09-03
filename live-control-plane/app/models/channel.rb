class Channel < ApplicationRecord
  validates :user_id, presence: true
  validates :arn, presence: true, uniqueness: true
  validates :ingest_endpoint, presence: true
  validates :playback_url, presence: true
  validates :stream_key_value, presence: true
end
