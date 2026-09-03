# frozen_string_literal: true

# Shared AWS IVS error handling and Channel JSON shaping for controllers
# that operate on Channel records via IvsChannelService.
module IvsChannelPresenter
  extend ActiveSupport::Concern

  included do
    rescue_from Aws::IVS::Errors::ServiceError, with: :render_ivs_error
    rescue_from IvsChannelService::StopStreamFailed, with: :render_conflict
  end

  private

  def channel_summary(channel)
    {
      id: channel.id,
      user_id: channel.user_id,
      name: channel.name,
      arn: channel.arn,
      ingest_endpoint: channel.ingest_endpoint,
      playback_url: channel.playback_url,
      authorized: channel.authorized,
      ivs_channel_type: channel.ivs_channel_type
    }
  end

  def render_ivs_error(error)
    render json: { error: error.message }, status: :bad_gateway
  end

  def render_conflict(error)
    render json: { error: error.message }, status: :conflict
  end

  def ivs_channel_service
    @ivs_channel_service ||= IvsChannelService.new
  end
end
