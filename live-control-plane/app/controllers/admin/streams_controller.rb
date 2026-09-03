# frozen_string_literal: true

# 運営者向けの操作。所有者(user_id)に関わらず、全チャネルの閲覧・強制停止・削除ができる。
module Admin
  class StreamsController < ApplicationController
    include MockAuthenticatable
    include IvsChannelPresenter

    # 全チャネル一覧（所有者に関わらず全件）
    def list
      channels = Channel.all
      render json: { channels: channels.map { |channel| channel_summary(channel) } }
    end

    # 配信の強制停止（所有者の操作を待たず、運営者が即座に止める）
    def stop_stream
      channel = find_channel
      return unless channel

      ivs_channel_service.stop_stream(arn: channel.arn)
      render json: { status: "stopped" }
    end

    # チャネル削除（配信中であれば強制停止してから削除し、DBレコードも削除する）
    def destroy
      channel = find_channel
      return unless channel

      ivs_channel_service.delete_channel(arn: channel.arn)
      channel.destroy!
      render json: { status: "deleted" }
    end

    private

    # 所有者を問わず、IDが一致するチャネルを取得する。見つからなければ404を返しnilを返す
    def find_channel
      channel = Channel.find_by(id: params[:channel_id])

      unless channel
        render json: { error: "channel not found" }, status: :not_found
        return nil
      end

      channel
    end
  end
end
