package usecase

import (
	"context"
)

type i480ObjectKeys []string
type i1080ObjectKeys []string
type thumbnailObjectKeys []string

type targetObjectKeys struct {
	I480ObjectKeys      i480ObjectKeys
	I1080ObjectKeys     i1080ObjectKeys
	ThumbnailObjectKeys thumbnailObjectKeys
}

// 1080p解像度の画像タグと480pの画像タグを付与する
func Exec(ctx context.Context) {
	// todo getTargetObjectKeys オブジェクトキー群を取得する
	// todo 各オブジェクトにtagを付与する。480p/  オブジェクトキー群を取得する
}
