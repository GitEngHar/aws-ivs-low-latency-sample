package usecase

import "context"

type IvsEventRoute interface {
	Exec(ctx context.Context)
}

type ivsEventRouteImpl struct{}

func NewIvsEventRoute(ctx context.Context) IvsEventRoute {
	return ivsEventRouteImpl{}
}

func (i ivsEventRouteImpl) Exec(ctx context.Context) {
	//todo EventBridgeから受け取ったイベントからchannel arnを抽出
	//todo channel arnからchannelのtagsを取得。tagの内容を標準出力する
}
