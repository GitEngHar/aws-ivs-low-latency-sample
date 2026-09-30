package usecase

import (
	"bytes"
	"context"
	"errors"
	"log"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ivs"
	"github.com/aws/aws-sdk-go-v2/service/ivs/types"
)

type fakeIvsClient struct {
	gotArn string
	err    error
}

func (f *fakeIvsClient) GetChannel(_ context.Context, in *ivs.GetChannelInput, _ ...func(*ivs.Options)) (*ivs.GetChannelOutput, error) {
	f.gotArn = aws.ToString(in.Arn)
	if f.err != nil {
		return nil, f.err
	}
	return &ivs.GetChannelOutput{Channel: &types.Channel{
		Arn:  in.Arn,
		Name: aws.String("my-channel"),
		Tags: map[string]string{"Env": "local"},
	}}, nil
}

const channelArn = "arn:aws:ivs:ap-northeast-1:123456789012:channel/abcd"

func ivsEvent(eventName string) []byte {
	return []byte(`{
		"id": "evt-1",
		"detail-type": "IVS Stream State Change",
		"source": "aws.ivs",
		"resources": ["` + channelArn + `"],
		"detail": {"event_name": "` + eventName + `", "channel_name": "my-channel", "stream_id": "st-1"}
	}`)
}

func captureLog(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	orig := log.Writer()
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(orig) })
	return &buf
}

func TestIvsEventRouteExec(t *testing.T) {
	for _, eventName := range []string{EVENT_TYPE_START, EVENT_TYPE_END, "Session Created"} {
		t.Run(eventName, func(t *testing.T) {
			buf := captureLog(t)
			client := &fakeIvsClient{}

			if err := NewIvsEventRoute(client).Exec(context.Background(), ivsEvent(eventName)); err != nil {
				t.Fatalf("Exec() error = %v", err)
			}
			if client.gotArn != channelArn {
				t.Errorf("GetChannel arn = %q, want %q", client.gotArn, channelArn)
			}
			out := buf.String()
			for _, want := range []string{eventName + ":", "channel_name=my-channel", "stream_id=st-1", "Env:local"} {
				if eventName == "Session Created" && want == eventName+":" {
					want = eventName + " (IVS Stream State Change):"
				}
				if !strings.Contains(out, want) {
					t.Errorf("log %q does not contain %q", out, want)
				}
			}
		})
	}
}

func TestIvsEventRouteExecErrors(t *testing.T) {
	captureLog(t)
	noResources := []byte(`{"id":"evt-1","detail":{"event_name":"Stream Start"},"resources":[]}`)
	if err := NewIvsEventRoute(&fakeIvsClient{}).Exec(context.Background(), noResources); err == nil {
		t.Error("Exec() without resources: want error")
	}
	failing := &fakeIvsClient{err: errors.New("boom")}
	if err := NewIvsEventRoute(failing).Exec(context.Background(), ivsEvent(EVENT_TYPE_START)); err == nil {
		t.Error("Exec() with GetChannel failure: want error")
	}
}
