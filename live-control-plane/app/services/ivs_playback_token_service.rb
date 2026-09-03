# frozen_string_literal: true

class IvsPlaybackTokenService
  def initialize(channel_arn:, user_id:)
    @channel_arn = channel_arn
    @user_id = user_id
  end

  def generate
    private_key = OpenSSL::PKey::EC.new(
      ENV.fetch('IVS_PLAYBACK_PRIVATE_KEY')
    )

    payload = {
      'aws:channel-arn': @channel_arn,
      'aws:viewer-id': @user_id,
      exp: 1.minute.from_now.to_i
    }

    JWT.encode(
      payload,
      private_key,
      'ES384'
    )
  end
end