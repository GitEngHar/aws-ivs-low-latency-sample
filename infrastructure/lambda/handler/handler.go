package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"lambda/usecase"
)

// リクエストルーティング -> usecase呼び出し
// 実行引数で呼び出すbatchを変える
func Handle(ctx context.Context, _ json.RawMessage) error {
	switch batch := os.Getenv("BATCH_NAME"); batch {
	case "ivs_event_route":
		usecase.NewIvsEventRoute(ctx).Exec(ctx)
	case "movie_delete":
		usecase.NewMovieDelete(ctx).Exec(ctx)
	case "resolution_tag_add":
		usecase.Exec(ctx)
	default:
		return fmt.Errorf("unknown BATCH_NAME: %q", batch)
	}
	return nil
}
