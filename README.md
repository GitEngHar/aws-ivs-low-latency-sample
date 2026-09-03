# AWS IVS 低レイテンシー配信サンプル

Amazon IVS (Interactive Video Service) を使った低レイテンシーライブ配信・視聴のサンプルプロジェクトです。
配信/視聴を行う `frontend`、チャンネル管理を行う `live-control-plane`、AWSリソースを管理する `infrastructure` の3つで構成されています。

## 機能一覧

### frontend (配信・視聴デモ)
- **配信 (Broadcast)**
  - カメラ・マイクを取得し、ブラウザから直接 IVS へ低レイテンシー配信 (`amazon-ivs-web-broadcast` SDK)
  - 配信プレビューを `canvas` に表示
- **視聴 (Player)**
  - IVS のプレイバック URL (`.m3u8`) を `video` 要素で低遅延再生 (`amazon-ivs-player` SDK)
- **環境変数の橋渡し**
  - ビルドツール不要の構成のため、`.env` の内容を `config.js` (`window.ENV`) に変換して読み込み

### live-control-plane (チャンネル管理バックエンド)
- Rails 製の API サーバーで、IVS チャンネルの作成・一覧取得・公開/非公開切り替えなどを管理
- フロントエンドからの Cross-Origin アクセスを許可する CORS 設定 (許可オリジンは環境変数で管理)

### infrastructure (AWS インフラ)
- Terraform による AWS リソース (IVS チャンネル等) のプロビジョニング・状態管理

## 前提条件

- Node.js (frontend の実行に必要)
- Ruby / Rails (live-control-plane の実行に必要)
- Terraform, AWS アカウント (infrastructure の実行に必要)
- Amazon IVS を利用するための AWS 権限

## ディレクトリ構成

```
.
├── frontend/            # 配信・視聴のWebデモ (詳細は frontend/README.md)
├── live-control-plane/   # チャンネル管理用 Rails API
└── infrastructure/       # Terraform による AWS インフラ定義
```

各ディレクトリのセットアップ手順・詳細は、それぞれの README を参照してください。


```bash
# Private Keyを生成
openssl ecparam -name secp384r1 -genkey -noout -out priv.pem

# Private KeyからPublic Keyを生成
openssl ec -in priv.pem -pubout -out public.pem
```