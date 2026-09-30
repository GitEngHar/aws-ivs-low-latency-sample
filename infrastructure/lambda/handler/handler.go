package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"lambda/usecase"
)

type Handler struct {
	s3Client  usecase.S3Client
	ivsClient usecase.IvsClient
}

func NewHandler(s3Client usecase.S3Client, ivsClient usecase.IvsClient) Handler {
	return Handler{s3Client: s3Client, ivsClient: ivsClient}
}

// リクエストルーティング -> usecase呼び出し
// 実行引数で呼び出すbatchを変える
func (h Handler) Handle(ctx context.Context, event json.RawMessage) error {
	switch batch := os.Getenv("BATCH_NAME"); batch {
	case "ivs_event_route":
		return usecase.NewIvsEventRoute(h.ivsClient).Exec(ctx, event)
	case "resolution_tag_add":
		return usecase.NewResolutionTagAdd(h.s3Client).Exec(ctx, event)
	default:
		return fmt.Errorf("unknown BATCH_NAME: %q", batch)
	}
}
