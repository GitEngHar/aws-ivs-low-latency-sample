require "test_helper"

class ChannelTest < ActiveSupport::TestCase
  def valid_attributes
    {
      user_id: "mock-user-1",
      name: "test-channel",
      arn: "arn:aws:ivs:ap-northeast-1:123456789012:channel/abc123",
      ingest_endpoint: "abc123.global-contribute.live-video.net",
      playback_url: "https://abc123.playback.live-video.net/api/video/v1/abc123.m3u8",
      stream_key_value: "sk_ap-northeast-1_abc123"
    }
  end

  test "valid with required attributes" do
    channel = Channel.new(valid_attributes)
    assert channel.valid?
  end

  test "defaults authorized to false and ivs_channel_type to STANDARD" do
    channel = Channel.create!(valid_attributes)
    assert_equal false, channel.authorized
    assert_equal "STANDARD", channel.ivs_channel_type
  end

  test "invalid without user_id" do
    channel = Channel.new(valid_attributes.merge(user_id: nil))
    assert_not channel.valid?
    assert_includes channel.errors[:user_id], "can't be blank"
  end

  test "invalid without arn" do
    channel = Channel.new(valid_attributes.merge(arn: nil))
    assert_not channel.valid?
    assert_includes channel.errors[:arn], "can't be blank"
  end

  test "invalid with duplicate arn" do
    Channel.create!(valid_attributes)
    duplicate = Channel.new(valid_attributes.merge(user_id: "mock-user-2"))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:arn], "has already been taken"
  end

  test "invalid without ingest_endpoint, playback_url, or stream_key_value" do
    %i[ingest_endpoint playback_url stream_key_value].each do |attr|
      channel = Channel.new(valid_attributes.merge(attr => nil))
      assert_not channel.valid?, "expected invalid without #{attr}"
    end
  end
end
