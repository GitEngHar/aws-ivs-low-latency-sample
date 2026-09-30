# AWS IVS 低レイテンシー配信サンプル

Amazon IVS (Interactive Video Service) を使った低レイテンシーライブ配信・視聴のサンプルプロジェクトです。
配信/視聴を行う `frontend`、チャンネル管理を行う `live-control-plane` (Rails API)、
周辺AWSリソースを管理する `infrastructure` (Terraform / Go Lambda) で構成されています。

## 機能一覧

### frontend (配信・視聴デモ)
- **配信前 通信品質チェック**: パブリックS3バケットへの直接GET/PUTで回線速度を計測し、対応可能な画質 (1080p/720p/480p) を判定
- **配信 (Broadcast)**: `live-control-plane` 経由でチャンネルを作成・選択し、カメラ/マイクからブラウザ直接IVSへ低レイテンシー配信 (`amazon-ivs-web-broadcast` SDK)。公開/非公開の切り替えも可能
- **視聴 (Player)**: `.m3u8` を `video` 要素で低遅延再生 (`amazon-ivs-player` SDK)。画質は手動/自動(ABR)切替、配信再開時は自動再接続
- **運営者 (Admin)**: 所有者に関わらず全チャンネルの一覧・強制配信停止・削除

### live-control-plane (チャンネル管理バックエンド)
- Rails製API。IVSチャンネルの作成・一覧取得・公開/非公開切り替え・配信停止・削除を管理
- プライベートチャンネル視聴用の再生トークン (JWT/ES384) 発行
- フロントエンドからのCross-Originアクセスを許可するCORS設定

### infrastructure (AWSリソース / 任意)
- IVSの Stream State Change / Stream Health Change イベントを EventBridge で捕捉し CloudWatch Logs に出力
- 録画用S3バケットと、解像度タグに応じたライフサイクルルール
- Go製Lambda (`infrastructure/lambda`)。現時点では雛形のみで、Terraformからのデプロイは未実装

## ディレクトリ構成

```
.
├── frontend/             # 配信・視聴のWebデモ (ビルドツール不要の静的ファイル)
├── live-control-plane/   # チャンネル管理用 Rails API (SQLite)
├── infrastructure/       # Terraform (EventBridge / CloudWatch Logs / S3)
│   └── lambda/           # Go製Lambda (雛形)
└── go.work               # infrastructure/lambda を含む Go workspace
```

## 構成とポート

```
ブラウザ (http://localhost:5500)
  ├─ frontend 静的ファイル ── npx serve (5500)
  ├─ REST API ─────────────▶ live-control-plane (http://localhost:3000) ──▶ AWS IVS API
  ├─ 配信 (Web Broadcast SDK) ─▶ AWS IVS ingest endpoint ──▶ 録画 ──▶ 録画用S3バケット
  ├─ 再生 (HLS .m3u8) ─────▶ AWS IVS playback URL
  └─ 通信品質チェック ─────▶ パブリックS3バケット (直接GET/PUT)
```

| コンポーネント | 起動コマンド | URL |
| --- | --- | --- |
| live-control-plane | `bin/rails server` | `http://localhost:3000` |
| frontend | `npx serve -l 5500` | `http://localhost:5500` |

## 前提条件

| ツール | バージョン | 用途 |
| --- | --- | --- |
| Ruby / Bundler | 3.4.5 (`live-control-plane/.ruby-version`) | Rails APIの実行 |
| SQLite | 3.8.0 以上 | Rails のDB |
| Node.js / npm | - | frontend の依存インストール・`config.js` 生成・静的配信 |
| AWS CLI | v2 | S3バケット準備・IVS再生キー登録 |
| OpenSSL | - | プライベートチャンネル再生用の鍵ペア生成 (任意) |
| Terraform | >= 1.5 | infrastructure の適用 (任意) |
| Go | 1.24 | Lambda のビルド (任意) |

AWS側で以下を用意しておくこと。

- Amazon IVS を利用できるAWSアカウントと、IAMユーザーのアクセスキー (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
  - `live-control-plane` はチャンネル作成時に `Env=local` タグを付与する。IAMポリシーを `Env=local` タグ条件で絞る場合の例は `infrastructure/verify.json` を参照
- 通信品質チェック用の、誰でもGET/PUTできるパブリックS3バケット (手順1で作成)
- 録画用のS3バケット (IVSチャンネルと同じリージョン。手順1で作成)
  - チャンネル作成時に録画設定 (Recording Configuration) も作成するため、このバケットがないとチャンネルを作成できない

## ローカル起動手順

以下、特に記載がない限りリポジトリのルートから実行する。

### 1. S3バケットの準備 (初回のみ)

#### 1-1. 通信品質チェック用バケット

frontend はブラウザから直接S3へGET/PUTして回線速度を計測するため、パブリックにGET/PUTできるバケットが必要。
既に用意済みの場合はスキップしてよい。

```bash
BUCKET=your-communication-quality-bucket   # 任意のバケット名に置き換える
REGION=ap-northeast-1

# バケット作成
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# ブロックパブリックアクセスを解除し、誰でも GET/PUT できるバケットポリシーを設定
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Effect\": \"Allow\",
    \"Principal\": \"*\",
    \"Action\": [\"s3:GetObject\", \"s3:PutObject\"],
    \"Resource\": \"arn:aws:s3:::$BUCKET/*\"
  }]
}"

# frontend のオリジン (http://localhost:5500) からのアクセスを許可するCORS設定
aws s3api put-bucket-cors --bucket "$BUCKET" \
  --cors-configuration file://live-control-plane/infra/s3-cors/test-communication-quality-bucket-cors.json

# ダウンロード計測用のダミーファイル (300MB) を生成してバケット直下に配置
mkfile 300m dummy_300mb.txt            # macOS。Linux では: dd if=/dev/zero of=dummy_300mb.txt bs=1M count=300
aws s3 cp dummy_300mb.txt "s3://$BUCKET/dummy_300mb.txt"
```

> ⚠️ このバケットは誰でも読み書きできる状態になる。検証用途専用とし、他のデータは置かないこと。

#### 1-2. 録画用バケット

チャンネル作成時に、`live-control-plane` がこのバケットを出力先とするIVSの録画設定を作成する。
パブリックアクセスは不要 (ブロックパブリックアクセスは有効のままでよい)。IVSの録画はサービスリンクロールで書き込むため、バケットポリシーの設定も不要。

```bash
RECORDING_BUCKET=your-recording-bucket   # 任意のバケット名に置き換える (IVSと同じリージョンに作成すること)

aws s3api create-bucket --bucket "$RECORDING_BUCKET" --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1
```

IAMユーザーには、IVSの権限に加えて `ivs:CreateRecordingConfiguration` / `ivs:GetRecordingConfiguration` と、
録画用バケットへの `s3:GetBucketLocation` / `s3:GetBucketPolicy` / `s3:ListBucket` の権限が必要 (例は `infrastructure/verify.json`)。

### 2. バックエンド (live-control-plane) のセットアップと起動

```bash
cd live-control-plane
bundle install
```

`live-control-plane/.env` を作成する (`.env-sample` は `.gitignore` 対象のため、クローン直後は存在しない場合がある。その場合は以下の内容で新規作成する)。

```
AWS_REGION=ap-northeast-1
AWS_ACCESS_KEY_ID=xxxxxx
AWS_SECRET_ACCESS_KEY=xxxxxx
IVS_PLAYBACK_PRIVATE_KEY="-----BEGIN EC PRIVATE KEY-----\nxxxxxx\n-----END EC PRIVATE KEY-----"

# 録画の出力先 (手順1-2で作成したバケット名)
AWS_S3_BUCKET_NAME=your-recording-bucket
```

| 変数名 | 用途 | 必須 |
| --- | --- | --- |
| `AWS_REGION` / `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | IVSチャンネルのCRUD・配信停止に使うAWS SDKクレデンシャル | 必須 |
| `AWS_S3_BUCKET_NAME` | チャンネル作成時に作る録画設定の出力先S3バケット名。未設定だとチャンネル作成が500エラーになる | 必須 |
| `IVS_PLAYBACK_PRIVATE_KEY` | プライベートチャンネルの再生トークン署名用EC秘密鍵 (PEM形式) | 任意 (下記参照) |

`.env` は `dotenv-rails` により development/test 環境で自動的に読み込まれる。
CORSは `config/initializers/cors.rb` ですべてのオリジンを許可しているため、frontend側のオリジンを設定する必要はない。

#### (任意) プライベートチャンネル用の再生キー

`IVS_PLAYBACK_PRIVATE_KEY` はパブリックチャンネルの配信・視聴では参照されないため、
基本のデモ動作だけなら未設定でも問題ない。チャンネルを**非公開(プライベート)に切り替えて視聴する**
機能を試す場合のみ、以下の手順で発行し公開鍵をIVSに登録した上で設定する
(未設定のままプライベート切替後に視聴すると、再生トークン発行時に500エラーになる)。

```bash
# 秘密鍵を生成
openssl ecparam -name secp384r1 -genkey -noout -out priv.pem

# 秘密鍵から公開鍵を生成
openssl ec -in priv.pem -pubout -out public.pem

# 公開鍵をAWS IVSに登録 (Playback Key Pairとしてインポート)
aws ivs import-playback-key-pair --public-key-material "$(base64 -i public.pem)"

# .env に貼り付ける1行形式 (改行を \n に置換) を出力
awk 'BEGIN{ORS="\\n"} {print}' priv.pem; echo
```

出力された文字列を `IVS_PLAYBACK_PRIVATE_KEY="..."` の値として設定する。
`*.pem` は `.gitignore` 対象だが、秘密鍵はコミットしないよう注意すること。

#### DB準備とサーバー起動

```bash
bin/rails db:prepare     # storage/development.sqlite3 を作成しマイグレーションを適用
bin/rails server         # http://localhost:3000
```

起動確認:

```bash
curl http://localhost:3000/up                                          # 200 が返ればOK
curl -H "X-User-Id: local-user" http://localhost:3000/live/streams/list  # {"channels":[]}
```

### 3. フロントエンド (frontend) のセットアップと起動

別ターミナルで実行する。`live-control-plane` が `3000` 番ポートを使うため、frontend は**別のポート** (`5500`) で配信する。

```bash
cd frontend
npm install
cp .env.example .env
```

`frontend/.env` を編集する。

```
# live-control-plane (Rails API) のベースURL
API_BASE_URL=http://localhost:3000

# 配信前の通信品質チェック用。手順1で作成したパブリックS3バケットのベースURL
BUCKET_BASE_URL=https://your-communication-quality-bucket.s3.ap-northeast-1.amazonaws.com
```

`.env` の内容からブラウザ側で読み込む `config.js` を生成し (`.env` を編集するたびに再実行)、静的ファイルを配信する。

```bash
npm run generate-config
npx serve -l 5500
```

`index.html` はES ModulesとカメラAPIを使うため、`file://` で直接開くことはできない。

### 4. 動作確認

ブラウザで `http://localhost:5500` を開く。

- **通信品質チェック**: 「通信速度をチェック」ボタンで回線速度を計測し、対応可能な画質を確認
- **配信側**: チャンネルを新規作成 (または一覧から選択) し、「配信開始」ボタンでカメラ/マイクの使用許可後に配信開始。公開設定の切替・配信停止も可能
- **視聴側**: チャンネルを選択し「視聴開始」ボタンで再生。画質は手動/自動(ABR)を切替可能
- **運営者**: 「一覧を更新」で全チャンネルを確認し、強制配信停止・削除が可能

配信と視聴を同時に確認する場合は、同じページを2つのタブで開き、片方で配信・もう片方で視聴するとよい。

> 💰 IVSチャンネルは配信中の時間に応じて課金される。確認後は「配信停止」し、不要なチャンネルは削除しておくこと。録画はS3に保存されるため、S3の保存料金も発生する。

### 5. (任意) infrastructure の適用

IVSイベントのログ出力や録画用バケットを試す場合のみ実施する。ローカル起動 (手順2〜4) には不要。

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars   # aws_region / aws_profile を必要に応じて編集

terraform init
terraform plan
terraform apply
```

- State はローカル (`infrastructure/terraform.tfstate`、gitignore 対象) に保存される。リモートバックエンドは未設定
- 作成されるリソース: EventBridge ルール (IVS Stream State Change / Stream Health Change)、CloudWatch Logs グループ (保持期間1日)、録画用S3バケットとライフサイクルルール
- イベントログの確認: `aws logs tail /aws/events/ivs-low-latency-sample/ivs-stream-state-change --follow`
- 片付け: `terraform destroy`

#### Lambda (Go) のビルド

`infrastructure/lambda` は `go.work` でワークスペースに含まれている。現時点では雛形 (各 usecase は TODO) で、Terraform からのデプロイ定義はまだない。
実行するバッチは環境変数 `BATCH_NAME` (`ivs_event_route` / `movie_delete` / `resolution_tag_add`) で切り替える。

```bash
cd infrastructure/lambda
go build ./...

# Lambda (provided.al2023 / arm64) 向けのバイナリを作る場合
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap .
```

## テスト

```bash
cd live-control-plane
bin/rails test       # ユニット/コントローラテスト
bin/rubocop          # Lint
bin/brakeman         # セキュリティスキャン
```

## トラブルシューティング

- `X-User-Id header is required` エラー: フロントエンドは固定のmock user idを自動付与するため、直接APIを叩く場合は `X-User-Id` ヘッダーを付与する
- チャンネル一覧の取得やチャンネル作成に失敗する場合: `live-control-plane` が起動しているか、`API_BASE_URL` の値が正しいかを確認する
- チャンネル作成が500エラーになる場合: `AWS_S3_BUCKET_NAME` が設定されているか、そのバケットがIVSと同じリージョンに存在するか、IAMユーザーに録画設定の作成権限があるかを確認する (Railsのログに原因が出る)
- チャンネル作成で録画設定の上限エラーになる場合: チャンネルを作るたびに録画設定 `defaultConfiguration` が新しく作られ、チャンネルを削除しても残る。不要なものを `aws ivs list-recording-configurations` で確認し、`aws ivs delete-recording-configuration --arn <arn>` で削除する
- チャンネル作成で `AccessDeniedException` になる場合: IAMユーザーに IVS の権限があるか確認する (`Env=local` タグ条件付きポリシーの例は `infrastructure/verify.json`)
- プライベートチャンネルの再生に失敗する場合: `IVS_PLAYBACK_PRIVATE_KEY` の秘密鍵に対応する公開鍵がAWS IVSにPlayback Key Pairとして登録されているか確認する
- カメラ/マイクが起動しない場合: ブラウザの権限設定、および `http://localhost` や `https://` などのセキュアコンテキストで開いているかを確認する
- 通信品質チェックが失敗する場合: `BUCKET_BASE_URL` のバケットが誰でもGET/PUTできる設定か、CORSで `http://localhost:5500` が許可されているか、`dummy_300mb.txt` が配置されているかを確認する
- `.env` を変更したのに frontend に反映されない場合: `npm run generate-config` を再実行し、ブラウザをリロードする
- 配信/再生に失敗する場合: ブラウザのコンソールログと選択中チャンネルの設定値 (ingest endpoint / stream key / playback URL) を確認する
