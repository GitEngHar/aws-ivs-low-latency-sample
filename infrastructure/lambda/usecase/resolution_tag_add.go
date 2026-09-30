package usecase

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"golang.org/x/sync/errgroup"
)

// S3ライフサイクルルール (s3.tf) のフィルタと一致させるタグ
const (
	resolutionTagKey       = "resolution"
	resolutionTag480       = "480"
	resolutionTag1080      = "1080"
	resolutionTagThumbnail = "thumbnail"

	recordingEndedSuffix = "events/recording-ended.json"
	tagConcurrency       = 16
)

type i480ObjectKeys []string
type i1080ObjectKeys []string
type thumbnailObjectKeys []string

type targetObjectKeys struct {
	I480ObjectKeys      i480ObjectKeys
	I1080ObjectKeys     i1080ObjectKeys
	ThumbnailObjectKeys thumbnailObjectKeys
}

// S3Client 本usecaseが利用するS3 APIのみを切り出したもの
type S3Client interface {
	s3.ListObjectsV2APIClient
	PutObjectTagging(ctx context.Context, params *s3.PutObjectTaggingInput, optFns ...func(*s3.Options)) (*s3.PutObjectTaggingOutput, error)
}

type ResolutionTagAdd interface {
	Exec(ctx context.Context, event json.RawMessage) error
}

type resolutionTagAddImpl struct {
	s3Client S3Client
}

func NewResolutionTagAdd(s3Client S3Client) ResolutionTagAdd {
	return resolutionTagAddImpl{s3Client: s3Client}
}

// Exec events/recording-ended.json のPUTイベントを受け取り、
// 同じ録画プレフィックス配下の1080p/480p動画とサムネイルに resolution タグを付与する
func (r resolutionTagAddImpl) Exec(ctx context.Context, event json.RawMessage) error {
	var s3Event events.S3Event
	if err := json.Unmarshal(event, &s3Event); err != nil {
		return fmt.Errorf("unmarshal s3 event: %w", err)
	}

	for _, record := range s3Event.Records {
		bucket := record.S3.Bucket.Name
		key := record.S3.Object.URLDecodedKey
		if !strings.HasSuffix(key, recordingEndedSuffix) {
			log.Printf("skip non recording-ended object: s3://%s/%s", bucket, key)
			continue
		}
		prefix := strings.TrimSuffix(key, recordingEndedSuffix)

		targets, err := r.getTargetObjectKeys(ctx, bucket, prefix)
		if err != nil {
			return err
		}
		if err := r.putTags(ctx, bucket, targets); err != nil {
			return err
		}
		log.Printf("tagged s3://%s/%s: 1080=%d 480=%d thumbnail=%d",
			bucket, prefix, len(targets.I1080ObjectKeys), len(targets.I480ObjectKeys), len(targets.ThumbnailObjectKeys))
	}
	return nil
}

// getTargetObjectKeys 録画プレフィックス配下のオブジェクトキー群を解像度別に取得する
func (r resolutionTagAddImpl) getTargetObjectKeys(ctx context.Context, bucket, prefix string) (targetObjectKeys, error) {
	var targets targetObjectKeys
	paginator := s3.NewListObjectsV2Paginator(r.s3Client, &s3.ListObjectsV2Input{
		Bucket: aws.String(bucket),
		Prefix: aws.String(prefix + "media/"),
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return targets, fmt.Errorf("list objects s3://%s/%s: %w", bucket, prefix, err)
		}
		for _, obj := range page.Contents {
			key := aws.ToString(obj.Key)
			switch resolutionOf(strings.TrimPrefix(key, prefix)) {
			case resolutionTag1080:
				targets.I1080ObjectKeys = append(targets.I1080ObjectKeys, key)
			case resolutionTag480:
				targets.I480ObjectKeys = append(targets.I480ObjectKeys, key)
			case resolutionTagThumbnail:
				targets.ThumbnailObjectKeys = append(targets.ThumbnailObjectKeys, key)
			}
		}
	}
	return targets, nil
}

// resolutionOf 録画プレフィックスからの相対キーを resolution タグ値に変換する。対象外は空文字
//
//	media/hls/1080p30/1.ts        -> 1080
//	media/hls/480p30/playlist.m3u8 -> 480
//	media/thumbnails/...           -> thumbnail
func resolutionOf(relKey string) string {
	if strings.HasPrefix(relKey, "media/thumbnails/") {
		return resolutionTagThumbnail
	}
	rendition, ok := strings.CutPrefix(relKey, "media/hls/")
	if !ok {
		return ""
	}
	rendition, _, ok = strings.Cut(rendition, "/")
	if !ok {
		return "" // media/hls/master.m3u8 など
	}
	switch {
	case strings.HasPrefix(rendition, "1080p"):
		return resolutionTag1080
	case strings.HasPrefix(rendition, "480p"):
		return resolutionTag480
	}
	return ""
}

// putTags 各オブジェクトに resolution タグを付与する
func (r resolutionTagAddImpl) putTags(ctx context.Context, bucket string, targets targetObjectKeys) error {
	g, ctx := errgroup.WithContext(ctx)
	g.SetLimit(tagConcurrency)
	put := func(keys []string, value string) {
		for _, key := range keys {
			g.Go(func() error {
				_, err := r.s3Client.PutObjectTagging(ctx, &s3.PutObjectTaggingInput{
					Bucket: aws.String(bucket),
					Key:    aws.String(key),
					Tagging: &types.Tagging{TagSet: []types.Tag{
						{Key: aws.String(resolutionTagKey), Value: aws.String(value)},
					}},
				})
				if err != nil {
					return fmt.Errorf("put object tagging s3://%s/%s: %w", bucket, key, err)
				}
				return nil
			})
		}
	}
	put(targets.I1080ObjectKeys, resolutionTag1080)
	put(targets.I480ObjectKeys, resolutionTag480)
	put(targets.ThumbnailObjectKeys, resolutionTagThumbnail)
	return g.Wait()
}
