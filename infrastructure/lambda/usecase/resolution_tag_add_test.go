package usecase

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type fakeS3Client struct {
	keys []string

	mu     sync.Mutex
	tagged map[string]string
}

func (f *fakeS3Client) ListObjectsV2(_ context.Context, in *s3.ListObjectsV2Input, _ ...func(*s3.Options)) (*s3.ListObjectsV2Output, error) {
	var contents []types.Object
	for _, k := range f.keys {
		if len(k) >= len(*in.Prefix) && k[:len(*in.Prefix)] == *in.Prefix {
			contents = append(contents, types.Object{Key: aws.String(k)})
		}
	}
	return &s3.ListObjectsV2Output{Contents: contents}, nil
}

func (f *fakeS3Client) PutObjectTagging(_ context.Context, in *s3.PutObjectTaggingInput, _ ...func(*s3.Options)) (*s3.PutObjectTaggingOutput, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.tagged[*in.Key] = *in.Tagging.TagSet[0].Value
	return &s3.PutObjectTaggingOutput{}, nil
}

func TestResolutionOf(t *testing.T) {
	cases := map[string]string{
		"media/hls/1080p60/1.ts":            "1080",
		"media/hls/1080p30/playlist.m3u8":   "1080",
		"media/hls/480p30/1.ts":             "480",
		"media/hls/720p30/1.ts":             "",
		"media/hls/master.m3u8":             "",
		"media/thumbnails/1080p/thumb0.jpg": "thumbnail",
		"events/recording-ended.json":       "",
	}
	for key, want := range cases {
		if got := resolutionOf(key); got != want {
			t.Errorf("resolutionOf(%q) = %q, want %q", key, got, want)
		}
	}
}

func TestResolutionTagAddExec(t *testing.T) {
	prefix := "ivs/v1/123456789012/abcd/2026/9/30/1/0/rec1/"
	other := "ivs/v1/123456789012/abcd/2026/9/30/2/0/rec2/"
	client := &fakeS3Client{
		keys: []string{
			prefix + "events/recording-started.json",
			prefix + "events/recording-ended.json",
			prefix + "media/hls/master.m3u8",
			prefix + "media/hls/1080p60/0.ts",
			prefix + "media/hls/480p30/0.ts",
			prefix + "media/thumbnails/1080p/thumb0.jpg",
			other + "media/hls/1080p60/0.ts",
		},
		tagged: map[string]string{},
	}

	// S3イベントのキーはURLエンコードされている
	event, _ := json.Marshal(map[string]any{
		"Records": []any{map[string]any{
			"s3": map[string]any{
				"bucket": map[string]any{"name": "bucket"},
				"object": map[string]any{"key": "ivs/v1/123456789012/abcd/2026/9/30/1/0/rec1/events/recording-ended.json"},
			},
		}},
	})

	if err := NewResolutionTagAdd(client).Exec(context.Background(), event); err != nil {
		t.Fatalf("Exec() error = %v", err)
	}

	want := map[string]string{
		prefix + "media/hls/1080p60/0.ts":            "1080",
		prefix + "media/hls/480p30/0.ts":             "480",
		prefix + "media/thumbnails/1080p/thumb0.jpg": "thumbnail",
	}
	if len(client.tagged) != len(want) {
		t.Fatalf("tagged = %v, want %v", client.tagged, want)
	}
	for k, v := range want {
		if client.tagged[k] != v {
			t.Errorf("tagged[%q] = %q, want %q", k, client.tagged[k], v)
		}
	}
}
