# frozen_string_literal: true

# チャンネル情報を取得する
# https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/IVS/Client.html?utm_source=chatgpt.comを参考に実装
module Live
  class StreamsController < ApplicationController
    include MockAuthenticatable
    include IvsChannelPresenter

    rescue_from IvsChannelService::AuthorizationSwitchFailed, with: :render_conflict

    # チャネル一覧（リクエストしたmock user idが所有するチャネルのみ、DBが正）
    def list
      channels = Channel.where(user_id: current_user_id)
      render json: { channels: channels.map { |channel| channel_summary(channel) } }
    end

    # チャネル作成（AWS IVS側の作成に成功した場合のみDBに永続化する）
    def create
      response = ivs_channel_service.create_channel(name: params[:name])

      channel = Channel.create!(
        user_id: current_user_id,
        name: response.channel.name,
        arn: response.channel.arn,
        ingest_endpoint: response.channel.ingest_endpoint,
        playback_url: response.channel.playback_url,
        stream_key_arn: response.stream_key.arn,
        stream_key_value: response.stream_key.value,
        ivs_channel_type: response.channel.type,
        authorized: response.channel.authorized
      )

      render json: { channel: channel_summary(channel) }, status: :created
    end

    # チャネル詳細（配信開始に必要なstream_key込み。所有者のみ取得可能）
    def show
      channel = find_owned_channel
      return unless channel

      render json: { channel: channel_detail(channel) }
    end

    # チャネルをプライベートに変更
    def change_to_private
      update_authorization(true)
    end

    # チャネルをパブリックに変更
    def change_to_public
      update_authorization(false)
    end

    # プライベートチャネル視聴に必要なトークンを生成する（?channel_id=... で対象を指定）
    # 発行したトークンは https://<playback_url>?token=<token> の形で再生URLに付与する
    def playback_token
      channel = find_owned_channel
      return unless channel

      unless channel.authorized
        render json: { error: "channel is public; playback token is not required" }, status: :unprocessable_entity
        return
      end

      token = IvsPlaybackTokenService.new(channel_arn: channel.arn, user_id: current_user_id).generate
      render json: { playback_token: token }
    end

    def user_kick
      channel_arn = "arn:aws:ivs:ap-northeast-1:363471485358:channel/J9w0Sxjy5SAJ"
      mock_user_id = "91E28B83-6B21-4F6E-B000-5004DE0FBACA" # viewer idになる
      response = ivs_client.start_viewer_session_revocation(
        channel_arn: channel_arn,
        viewer_id: mock_user_id
      )
      render json: { response: response.successful? }
    end

    # 自チャネルの配信を停止する
    def stop_stream
      channel = find_owned_channel
      return unless channel

      ivs_channel_service.stop_stream(arn: channel.arn)
      render json: { status: "stopped" }
    end

    # 自チャネルを削除する（配信中であれば停止してから削除し、DBレコードも削除する）
    def delete_channel
      channel = find_owned_channel
      return unless channel

      ivs_channel_service.delete_channel(arn: channel.arn)
      channel.destroy!
      render json: { status: "deleted" }
    end

    private

    def update_authorization(authorized)
      channel = find_owned_channel
      return unless channel

      ivs_channel_service.update_authorization(arn: channel.arn, authorized: authorized)
      channel.update!(authorized: authorized)

      render json: { channel: channel_summary(channel) }
    end

    # 所有者(current_user_id)のチャネルのみ取得。見つからなければ404を返しnilを返す
    def find_owned_channel
      channel = Channel.find_by(id: params[:channel_id], user_id: current_user_id)

      unless channel
        render json: { error: "channel not found" }, status: :not_found
        return nil
      end

      channel
    end

    # stream_keyはブロードキャスト開始に必要なため show でのみ含める
    def channel_detail(channel)
      channel_summary(channel).merge(stream_key_value: channel.stream_key_value)
    end

    def ivs_client
      @ivs_client ||= Aws::IVS::Client.new(
        region: ENV.fetch("AWS_REGION", "ap-northeast-1"),
        access_key_id: ENV["AWS_ACCESS_KEY_ID"],
        secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
      )
    end
  end
end
