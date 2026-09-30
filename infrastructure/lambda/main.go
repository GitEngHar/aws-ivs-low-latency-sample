package main

// lambda起動
import (
	"context"
	"log"

	"lambda/handler"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ivs"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// 依存関係の解決
func main() {
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("load aws config: %v", err)
	}
	lambda.Start(handler.NewHandler(s3.NewFromConfig(cfg), ivs.NewFromConfig(cfg)).Handle)
}
