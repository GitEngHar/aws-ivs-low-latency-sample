require "test_helper"
require "ostruct"

class IvsChannelServiceTest < ActiveSupport::TestCase
  RECORDING_CONFIGURATION_ARN = "arn:aws:ivs:ap-northeast-1:123456789012:recording-configuration/rc1"

  class FakeIvsClient
    attr_reader :create_channel_args, :update_channel_args, :tag_resource_args, :create_recording_configuration_args

    def initialize(create_response:, update_response:)
      @create_response = create_response
      @update_response = update_response
    end

    def create_recording_configuration(args)
      @create_recording_configuration_args = args
      OpenStruct.new(recording_configuration: OpenStruct.new(arn: RECORDING_CONFIGURATION_ARN))
    end

    def get_recording_configuration(arn:)
      OpenStruct.new(recording_configuration: OpenStruct.new(arn: arn, state: "ACTIVE"))
    end

    def create_channel(args)
      @create_channel_args = args
      @create_response
    end

    def update_channel(args)
      @update_channel_args = args
      @update_response
    end

    # The channel is never live in these tests, matching IVS's behavior of
    # raising ChannelNotBroadcasting from GetStream when there is no stream.
    def get_stream(channel_arn:)
      raise Aws::IVS::Errors::ChannelNotBroadcasting.new(nil, "not broadcasting")
    end

    def tag_resource(args)
      @tag_resource_args = args
    end
  end

  setup do
    @original_bucket_name = ENV["AWS_S3_BUCKET_NAME"]
    ENV["AWS_S3_BUCKET_NAME"] = "test-recording-bucket"
  end

  teardown do
    ENV["AWS_S3_BUCKET_NAME"] = @original_bucket_name
  end

  test "create_channel calls the IVS client with the given name and a public STANDARD channel request" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    result = service.create_channel(name: "my-channel")

    assert_equal({ type: "STANDARD", authorized: false, name: "my-channel", recording_configuration_arn: RECORDING_CONFIGURATION_ARN }, client.create_channel_args)
    assert_equal fake_response, result
  end

  test "create_channel omits the name param when no name is given, letting AWS default it" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel

    assert_equal({ type: "STANDARD", authorized: false, recording_configuration_arn: RECORDING_CONFIGURATION_ARN }, client.create_channel_args)
  end

  test "create_channel passes tags through to the IVS client when given" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1", arn: "arn:sk:1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel(name: "my-channel", tags: { "Env" => "local" })

    assert_equal(
      { type: "STANDARD", authorized: false, name: "my-channel", tags: { "Env" => "local" }, recording_configuration_arn: RECORDING_CONFIGURATION_ARN },
      client.create_channel_args
    )
  end

  test "create_channel also tags the auto-created stream key when tags are given" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1", arn: "arn:sk:1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel(name: "my-channel", tags: { "Env" => "local" })

    assert_equal({ resource_arn: "arn:sk:1", tags: { "Env" => "local" } }, client.tag_resource_args)
  end

  test "create_channel does not tag the stream key when no tags are given" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1", arn: "arn:sk:1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel(name: "my-channel")

    assert_nil client.tag_resource_args
  end

  test "create_channel creates a recording configuration targeting AWS_S3_BUCKET_NAME before the channel" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel(name: "my-channel")

    assert_equal(
      { s3: { bucket_name: "test-recording-bucket" } },
      client.create_recording_configuration_args[:destination_configuration]
    )
  end

  test "create_channel records both the 1080p (FULL_HD) and 480p (SD) renditions" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel(name: "my-channel")

    assert_equal(
      { rendition_selection: "CUSTOM", renditions: %w[FULL_HD SD] },
      client.create_recording_configuration_args[:rendition_configuration]
    )
  end

  test "update_authorization calls the IVS client with the given arn and authorized flag" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1", authorized: true))
    client = FakeIvsClient.new(create_response: nil, update_response: fake_response)
    service = IvsChannelService.new(client: client)

    result = service.update_authorization(arn: "arn:1", authorized: true)

    assert_equal({ arn: "arn:1", authorized: true }, client.update_channel_args)
    assert_equal fake_response, result
  end

  test "propagates errors raised by the IVS client" do
    client = FakeIvsClient.new(create_response: nil, update_response: nil)
    def client.create_channel(*)
      raise Aws::IVS::Errors::ServiceError.new(nil, "boom")
    end
    service = IvsChannelService.new(client: client)

    assert_raises(Aws::IVS::Errors::ServiceError) do
      service.create_channel(name: "my-channel")
    end
  end
end
