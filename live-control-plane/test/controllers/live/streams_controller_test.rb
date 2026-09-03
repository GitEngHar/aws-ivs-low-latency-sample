require "test_helper"
require "ostruct"

module Live
  class StreamsControllerTest < ActionDispatch::IntegrationTest
    # minitest 6 no longer bundles Object#stub; swap IvsChannelService.new
    # for the duration of the block without pulling in an extra gem.
    def stub_ivs_channel_service(fake)
      IvsChannelService.define_singleton_method(:new) { fake }
      yield
    ensure
      IvsChannelService.singleton_class.send(:remove_method, :new)
    end
    class FakeIvsChannelService
      Response = Struct.new(:channel, :stream_key)

      def create_channel(name: nil)
        OpenStruct.new(
          channel: OpenStruct.new(
            name: name || "-",
            arn: "arn:aws:ivs:ap-northeast-1:123456789012:channel/new123",
            ingest_endpoint: "new123.global-contribute.live-video.net",
            playback_url: "https://new123.playback.live-video.net/api/video/v1/new123.m3u8",
            type: "STANDARD",
            authorized: false
          ),
          stream_key: OpenStruct.new(arn: "arn:aws:ivs:ap-northeast-1:123456789012:stream-key/sk123", value: "sk_ap-northeast-1_new123")
        )
      end

      def update_authorization(arn:, authorized:)
        OpenStruct.new(channel: OpenStruct.new(arn: arn, authorized: authorized))
      end
    end

    class FailingIvsChannelService
      def create_channel(*)
        raise Aws::IVS::Errors::ServiceError.new(nil, "boom")
      end

      def update_authorization(*)
        raise Aws::IVS::Errors::ServiceError.new(nil, "boom")
      end
    end

    def owned_channel(user_id: "user-1", authorized: false)
      unique = SecureRandom.hex(4)
      Channel.create!(
        user_id: user_id,
        name: "existing-channel-#{unique}",
        arn: "arn:aws:ivs:ap-northeast-1:123456789012:channel/existing-#{unique}",
        ingest_endpoint: "existing-#{unique}.global-contribute.live-video.net",
        playback_url: "https://existing-#{unique}.playback.live-video.net/api/video/v1/existing-#{unique}.m3u8",
        stream_key_value: "sk_ap-northeast-1_existing-#{unique}",
        authorized: authorized
      )
    end

    test "create without X-User-Id is rejected" do
      post "/live/streams/create"
      assert_response :unauthorized
    end

    test "create persists a channel and omits the stream key from the response" do
      stub_ivs_channel_service(FakeIvsChannelService.new) do
        assert_difference("Channel.count", 1) do
          post "/live/streams/create", headers: { "X-User-Id" => "user-1" }, params: { name: "my-channel" }
        end
      end

      assert_response :created
      body = response.parsed_body
      assert_equal "user-1", Channel.last.user_id
      assert_not body["channel"].key?("stream_key_value")
      assert_equal "arn:aws:ivs:ap-northeast-1:123456789012:channel/new123", body["channel"]["arn"]
    end

    test "create does not persist a channel when the IVS call fails" do
      stub_ivs_channel_service(FailingIvsChannelService.new) do
        assert_no_difference("Channel.count") do
          post "/live/streams/create", headers: { "X-User-Id" => "user-1" }
        end
      end

      assert_response :bad_gateway
    end

    test "list returns only the requesting user's channels" do
      owned_channel(user_id: "user-1")
      owned_channel(user_id: "user-2")

      get "/live/streams/list", headers: { "X-User-Id" => "user-1" }

      assert_response :success
      channels = response.parsed_body["channels"]
      assert_equal 1, channels.length
      assert_equal "user-1", Channel.find(channels.first["id"]).user_id
    end

    test "list returns an empty array for a user with no channels" do
      get "/live/streams/list", headers: { "X-User-Id" => "user-with-no-channels" }

      assert_response :success
      assert_equal [], response.parsed_body["channels"]
    end

    test "show includes the stream key for the owner" do
      channel = owned_channel(user_id: "user-1")

      get "/live/streams/show", headers: { "X-User-Id" => "user-1" }, params: { channel_id: channel.id }

      assert_response :success
      assert_equal channel.stream_key_value, response.parsed_body["channel"]["stream_key_value"]
    end

    test "show returns not found for another user's channel" do
      channel = owned_channel(user_id: "user-1")

      get "/live/streams/show", headers: { "X-User-Id" => "user-2" }, params: { channel_id: channel.id }

      assert_response :not_found
    end

    test "change_to_private updates the persisted channel and calls IVS" do
      channel = owned_channel(user_id: "user-1", authorized: false)

      stub_ivs_channel_service(FakeIvsChannelService.new) do
        post "/live/streams/change_to_private", headers: { "X-User-Id" => "user-1" }, params: { channel_id: channel.id }
      end

      assert_response :success
      assert_equal true, channel.reload.authorized
      assert_equal true, response.parsed_body["channel"]["authorized"]
    end

    test "change_to_public rejects a channel not owned by the requester" do
      channel = owned_channel(user_id: "user-1", authorized: true)

      post "/live/streams/change_to_public", headers: { "X-User-Id" => "user-2" }, params: { channel_id: channel.id }

      assert_response :not_found
      assert_equal true, channel.reload.authorized
    end

    test "change_to_private leaves the persisted state unchanged when the IVS call fails" do
      channel = owned_channel(user_id: "user-1", authorized: false)

      stub_ivs_channel_service(FailingIvsChannelService.new) do
        post "/live/streams/change_to_private", headers: { "X-User-Id" => "user-1" }, params: { channel_id: channel.id }
      end

      assert_response :bad_gateway
      assert_equal false, channel.reload.authorized
    end
  end
end
