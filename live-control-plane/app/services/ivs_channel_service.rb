# frozen_string_literal: true

# Sole place that talks to Aws::IVS::Client for channel create/update,
# isolating the AWS SDK shape from the controller.
class IvsChannelService
  # Raised when authorized could not be switched within MAX_STOP_CHECK_ATTEMPTS.
  class AuthorizationSwitchFailed < StandardError; end

  # Raised when a channel could not be confirmed stopped within MAX_STOP_CHECK_ATTEMPTS.
  class StopStreamFailed < StandardError; end

  # UpdateChannel rejects requests while the channel is still live, so a stream
  # stopped moments ago may not be reflected yet. Poll until IVS confirms the
  # channel is no longer broadcasting before attempting the switch.
  MAX_STOP_CHECK_ATTEMPTS = 10
  STOP_CHECK_INTERVAL = 1 # seconds

  def initialize(client: default_client)
    @client = client
  end

  # Tag keys re-applied to the auto-created stream key (a subset of the
  # channel's tags). Only "Env" is needed there, so other channel tags
  # (e.g. a future channel-name tag) are not copied over.
  STREAM_KEY_TAG_KEYS = %w[Env].freeze

  # Creates a new public STANDARD IVS channel.
  # A blank name is omitted so AWS applies its own default naming.
  #
  # CreateChannel auto-creates a stream key for the channel, but its `tags`
  # param only tags the channel resource, not that stream key. So a subset
  # of those tags (STREAM_KEY_TAG_KEYS) is re-applied to the stream key via
  # TagResource after creation.
  #
  # Raises Aws::IVS::Errors::ServiceError on failure.
  def create_channel(name: nil, tags: nil)
    params = { type: "STANDARD", authorized: false }
    params[:name] = name if name.present?
    params[:tags] = tags if tags.present?

    response = @client.create_channel(params)

    stream_key_tags = tags&.slice(*STREAM_KEY_TAG_KEYS)
    @client.tag_resource(resource_arn: response.stream_key.arn, tags: stream_key_tags) if stream_key_tags.present?

    response
  end

  # ListStreamKeys rejects max_results above this.
  LIST_STREAM_KEYS_MAX_RESULTS = 50

  # Lists every stream key for a channel. ListStreamKeys defaults to
  # max_results: 1, so this pages through next_token until exhausted rather
  # than silently returning a truncated list.
  #
  # Raises Aws::IVS::Errors::ServiceError on failure.
  def list_stream_keys(arn:)
    stream_keys = []
    next_token = nil

    loop do
      params = { channel_arn: arn, max_results: LIST_STREAM_KEYS_MAX_RESULTS }
      params[:next_token] = next_token if next_token.present?

      response = @client.list_stream_keys(params)
      stream_keys.concat(response.stream_keys)

      next_token = response.next_token
      break if next_token.blank?
    end

    stream_keys
  end

  # Flips an existing channel's authorized (private) flag.
  #
  # IVS refuses to update a channel while it is still broadcasting, so a stream
  # stopped just before this call may not have propagated yet. Poll up to
  # MAX_STOP_CHECK_ATTEMPTS times (once per STOP_CHECK_INTERVAL) for the channel
  # to stop, then attempt the switch as soon as it does.
  #
  # Raises Aws::IVS::Errors::ServiceError on an AWS-side failure, or
  # AuthorizationSwitchFailed if the channel never stopped (or never switched)
  # within the retry budget.
  def update_authorization(arn:, authorized:)
    MAX_STOP_CHECK_ATTEMPTS.times do |attempt|
      if channel_stopped?(arn)
        response = @client.update_channel(arn: arn, authorized: authorized)
        return response if response.channel.authorized == authorized
      end

      sleep(STOP_CHECK_INTERVAL) unless attempt == MAX_STOP_CHECK_ATTEMPTS - 1
    end

    raise AuthorizationSwitchFailed, "channel did not stop broadcasting in time to switch authorized (arn=#{arn})"
  end

  # Force-stops a channel's live stream (operator action). A no-op if the
  # channel is already stopped.
  #
  # Raises Aws::IVS::Errors::ServiceError on an AWS-side failure, or
  # StopStreamFailed if IVS never confirms the channel stopped within the
  # retry budget.
  def stop_stream(arn:)
    return if channel_stopped?(arn)

    @client.stop_stream(channel_arn: arn)
    wait_until_stopped!(arn)
  end

  # Deletes a channel from AWS IVS. IVS refuses to delete a live channel
  # (409 ConflictException), so the stream is stopped and confirmed stopped
  # first.
  #
  # Raises Aws::IVS::Errors::ServiceError on an AWS-side failure, or
  # StopStreamFailed if the channel could not be confirmed stopped.
  def delete_channel(arn:)
    stop_stream(arn: arn)
    @client.delete_channel(arn: arn)
  end

  private

  def wait_until_stopped!(arn)
    MAX_STOP_CHECK_ATTEMPTS.times do |attempt|
      return if channel_stopped?(arn)

      sleep(STOP_CHECK_INTERVAL) unless attempt == MAX_STOP_CHECK_ATTEMPTS - 1
    end

    raise StopStreamFailed, "channel did not stop broadcasting in time (arn=#{arn})"
  end

  # IVS raises ChannelNotBroadcasting from GetStream once there is no active stream.
  def channel_stopped?(arn)
    @client.get_stream(channel_arn: arn)
    false
  rescue Aws::IVS::Errors::ChannelNotBroadcasting
    true
  end

  def default_client
    Aws::IVS::Client.new(
      region: ENV.fetch("AWS_REGION", "ap-northeast-1"),
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
    )
  end
end
