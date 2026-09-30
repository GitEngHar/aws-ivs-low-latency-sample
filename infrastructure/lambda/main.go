package main

// lambda起動
import (
	"lambda/handler"

	"github.com/aws/aws-lambda-go/lambda"
)

// 依存関係の解決
func main() {
	lambda.Start(handler.Handle)
}
