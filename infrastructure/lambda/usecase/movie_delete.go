package usecase

import "context"

type MovieDelete interface {
	Exec(ctx context.Context)
}

type movieDeleteImpl struct{}

func NewMovieDelete(ctx context.Context) MovieDelete {
	return movieDeleteImpl{}
}

// Exec 毎分呼び出され画像と動画を削除する
func (i movieDeleteImpl) Exec(ctx context.Context) {
	//todo 1080pのタグ情報を持つ動画は2分経過していれば削除
	//todo thumbnailの画像は3分で削除
}
