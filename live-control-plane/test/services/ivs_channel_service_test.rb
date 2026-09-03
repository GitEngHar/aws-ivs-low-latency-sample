require "test_helper"
require "ostruct"

class IvsChannelServiceTest < ActiveSupport::TestCase
  class FakeIvsClient
    attr_reader :create_channel_args, :update_channel_args

    def initialize(create_response:, update_response:)
      @create_response = create_response
      @update_response = update_response
    end

    def create_channel(args)
      @create_channel_args = args
      @create_response
    end

    def update_channel(args)
      @update_channel_args = args
      @update_response
    end
  end

  test "create_channel calls the IVS client with the given name and a public STANDARD channel request" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    result = service.create_channel(name: "my-channel")

    assert_equal({ type: "STANDARD", authorized: false, name: "my-channel" }, client.create_channel_args)
    assert_equal fake_response, result
  end

  test "create_channel omits the name param when no name is given, letting AWS default it" do
    fake_response = OpenStruct.new(channel: OpenStruct.new(arn: "arn:1"), stream_key: OpenStruct.new(value: "sk_1"))
    client = FakeIvsClient.new(create_response: fake_response, update_response: nil)
    service = IvsChannelService.new(client: client)

    service.create_channel

    assert_equal({ type: "STANDARD", authorized: false }, client.create_channel_args)
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
    client = Object.new
    def client.create_channel(*)
      raise Aws::IVS::Errors::ServiceError.new(nil, "boom")
    end
    service = IvsChannelService.new(client: client)

    assert_raises(Aws::IVS::Errors::ServiceError) do
      service.create_channel(name: "my-channel")
    end
  end
end
