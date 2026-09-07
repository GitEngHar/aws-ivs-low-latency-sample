# AWS IVS 低レイテンシー配信サンプル

Amazon IVS (Interactive Video Service) を使った低レイテンシーライブ配信・視聴のサンプルプロジェクトです。
配信/視聴を行う `frontend` と、チャンネル管理を行う `live-control-plane` (Rails API) の2つで構成されています。

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

## ディレクトリ構成

```
.
├── frontend/            # 配信・視聴のWebデモ
└── live-control-plane/   # チャンネル管理用 Rails API
```

## 前提条件

- Node.js (npmが使えること)
- Ruby 3.4.5 / Bundler (Railsの実行に必要)
- Amazon IVSを利用できるAWSアカウント・IAMクレデンシャル (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
- OpenSSL (プライベートチャンネル再生用の鍵ペア生成に使用)
- 通信品質チェック用に、誰でもGET/PUTできるパブリックS3バケット (直下にダウンロード計測用のダミーファイルを配置)

## 動作手順

### 1. バックエンド (live-control-plane) のセットアップ

```bash
cd live-control-plane
bundle install
```

`.env-sample` を参考に `live-control-plane/.env` を作成する。

```bash
cp .env-sample .env
```

```
AWS_REGION=ap-northeast-1
AWS_ACCESS_KEY_ID=xxxxxx
AWS_SECRET_ACCESS_KEY=xxxxxx
IVS_PLAYBACK_PRIVATE_KEY="-----BEGIN EC PRIVATE KEY-----\nxxxxxx\n-----END EC PRIVATE KEY-----"

# frontendを配信するオリジン (CORS許可オリジン)
FRONTEND_ORIGINS=http://localhost:5500
```

| 変数名 | 用途 | 必須 |
| --- | --- | --- |
| `AWS_REGION` / `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | IVSチャンネルのCRUD・配信停止に使うAWS SDKクレデンシャル | 必須 |
| `FRONTEND_ORIGINS` | CORSで許可するフロントエンドのオリジン | 必須 |
| `IVS_PLAYBACK_PRIVATE_KEY` | プライベートチャンネルの再生トークン署名用EC秘密鍵 (PEM形式) | 任意 (下記参照) |

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
```

生成した `priv.pem` の中身を1行の `.env` の値 (改行は `\n` に置換) として `IVS_PLAYBACK_PRIVATE_KEY` に設定する。

データベースの準備とサーバー起動 (デフォルトで `http://localhost:3000`):

```bash
bin/rails db:prepare
bin/rails server
```

### 2. フロントエンド (frontend) のセットアップ

`live-control-plane` はデフォルトで `3000` 番ポートを使うため、frontendは**別のポート** (例: `5500`) で配信する。

```bash
cd frontend
npm install
```

`.env.example` を参考に `frontend/.env` を作成する。

```bash
cp .env.example .env
```

```
# live-control-plane (Rails API) のベースURL
API_BASE_URL=http://localhost:3000

# 配信前の通信品質チェック用。誰でもGET/PUTできるパブリックS3バケットのベースURL
BUCKET_BASE_URL=https://xxxxxx.s3.ap-northeast-1.amazonaws.com
```

`.env` の内容からブラウザ側で読み込む `config.js` を生成する (`.env` を編集するたびに再実行):

```bash
npm run generate-config
```

静的ファイルをローカルサーバーで配信する (`index.html` はES ModulesとカメラAPIを使うため `file://` では開けない):

```bash
npx serve -l 5500
```

### 3. 動作確認

ブラウザで `http://localhost:5500` を開く。

- **通信品質チェック**: 「通信速度をチェック」ボタンで回線速度を計測し、対応可能な画質を確認
- **配信側**: チャンネルを新規作成 (または一覧から選択) し、「配信開始」ボタンでカメラ/マイクの使用許可後に配信開始。公開設定の切替・配信停止も可能
- **視聴側**: チャンネルを選択し「視聴開始」ボタンで再生。画質は手動/自動(ABR)を切替可能
- **運営者**: 「一覧を更新」で全チャンネルを確認し、強制配信停止・削除が可能

## トラブルシューティング

- `X-User-Id header is required` エラー: フロントエンドは固定のmock user idを自動付与するため、直接APIを叩く場合は `X-User-Id` ヘッダーを付与する
- チャンネル一覧の取得やチャンネル作成に失敗する場合: `live-control-plane` が起動しているか、`API_BASE_URL` の値が正しいか、`FRONTEND_ORIGINS` にfrontendのオリジンが含まれているかを確認する
- プライベートチャンネルの再生に失敗する場合: `IVS_PLAYBACK_PRIVATE_KEY` の秘密鍵に対応する公開鍵がAWS IVSにPlayback Key Pairとして登録されているか確認する
- カメラ/マイクが起動しない場合: ブラウザの権限設定、および `http://localhost` や `https://` などのセキュアコンテキストで開いているかを確認する
- 通信品質チェックが失敗する場合: `BUCKET_BASE_URL` のバケットが誰でもGET/PUTできる設定になっているか、ダウンロード計測用のダミーファイルが配置されているかを確認する
- 配信/再生に失敗する場合: ブラウザのコンソールログと選択中チャンネルの設定値 (ingest endpoint / stream key / playback URL) を確認する
