package usecase

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ivs"
)

const (
	EVENT_TYPE_START = "Stream Start"
	EVENT_TYPE_END   = "Stream End"
)

// IvsClient 本usecaseが利用するIVS APIのみを切り出したもの
type IvsClient interface {
	GetChannel(ctx context.Context, params *ivs.GetChannelInput, optFns ...func(*ivs.Options)) (*ivs.GetChannelOutput, error)
}

// ivsStreamEventDetail IVS Stream State Change / Stream Health Change イベントの detail
type ivsStreamEventDetail struct {
	EventName   string `json:"event_name"`
	ChannelName string `json:"channel_name"`
	StreamID    string `json:"stream_id"`
}

type IvsEventRoute interface {
	Exec(ctx context.Context, event json.RawMessage) error
}

type ivsEventRouteImpl struct {
	ivsClient IvsClient
}

func NewIvsEventRoute(ivsClient IvsClient) IvsEventRoute {
	return ivsEventRouteImpl{ivsClient: ivsClient}
}

// Exec EventBridgeから受け取ったIVSイベントのchannel arnでchannel情報を取得し、
// イベント種別ごとに標準出力を行う
func (i ivsEventRouteImpl) Exec(ctx context.Context, event json.RawMessage) error {
	var e events.EventBridgeEvent
	if err := json.Unmarshal(event, &e); err != nil {
		return fmt.Errorf("unmarshal eventbridge event: %w", err)
	}
	var detail ivsStreamEventDetail
	if err := json.Unmarshal(e.Detail, &detail); err != nil {
		return fmt.Errorf("unmarshal ivs event detail: %w", err)
	}
	// IVSイベントの resources には対象channelのarnが1件入る
	if len(e.Resources) == 0 {
		return fmt.Errorf("channel arn not found in event resources: id=%s", e.ID)
	}
	channelArn := e.Resources[0]

	out, err := i.ivsClient.GetChannel(ctx, &ivs.GetChannelInput{Arn: aws.String(channelArn)})
	if err != nil {
		return fmt.Errorf("get channel %s: %w", channelArn, err)
	}
	channel := out.Channel

	switch detail.EventName {
	case EVENT_TYPE_START:
		log.Printf("%s: channel_arn=%s channel_name=%s stream_id=%s latency_mode=%s type=%s recording_configuration_arn=%s tags=%v",
			EVENT_TYPE_START, channelArn, aws.ToString(channel.Name), detail.StreamID,
			channel.LatencyMode, channel.Type, aws.ToString(channel.RecordingConfigurationArn), channel.Tags)
		viewTags(channel.Tags)
	case EVENT_TYPE_END:
		log.Printf("%s: channel_arn=%s channel_name=%s stream_id=%s tags=%v",
			EVENT_TYPE_END, channelArn, aws.ToString(channel.Name), detail.StreamID, channel.Tags)
		viewTags(channel.Tags)
	default:
		log.Printf("%s (%s): channel_arn=%s channel_name=%s stream_id=%s tags=%v",
			detail.EventName, e.DetailType, channelArn, aws.ToString(channel.Name), detail.StreamID, channel.Tags)
		viewTags(channel.Tags)
	}
	return nil
}

func viewTags(channelTags map[string]string) {
	for v, k := range channelTags {
		log.Printf("%s %s", v, k)
	}
}
