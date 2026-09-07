# AWS IVS 低レイテンシー配信 & 視聴 デモ (frontend)

Amazon IVS (Interactive Video Service) の Web Broadcast SDK と Player SDK を使った、
ビルドツール不要の低レイテンシーライブ配信・視聴デモです。
チャンネルの作成・一覧・公開設定の管理はバックエンド (`live-control-plane`, Rails API) 経由で行います。

## 機能一覧

- **配信前 通信品質チェック (communication-quality.js)**
  - `live-control-plane` を経由せず、ブラウザから直接パブリックS3バケットへ
    GET/PUT してダウンロード/アップロード速度を計測
  - 実測アップロード速度から 1080p / 720p / 480p のうちどこまで安定配信できるかを判定
- **配信 (Broadcast)**
  - `live-control-plane` API でチャンネルの作成・一覧取得・選択を行う
  - カメラ・マイクを取得し、選択したチャンネルへブラウザから直接ライブ配信
    (`amazon-ivs-web-broadcast` SDK)
  - `canvas` 要素に配信プレビューを表示、解像度プリセットを切り替え可能
  - チャンネルの公開/非公開 (パブリック/プライベート) 切り替え
- **視聴 (Player)**
  - `live-control-plane` API でチャンネル一覧・再生情報 (プライベートの場合は再生トークン) を取得
  - `.m3u8` を `video` 要素で低遅延再生し、画質を手動/自動 (ABR) で切り替え可能
    (`amazon-ivs-player` SDK)
  - 配信側の公開設定切り替えなどで再生が途切れた場合、自動的に再接続を試行
- **運営者 (Admin)**
  - 所有者に関わらず全チャンネルの一覧表示、強制配信停止、チャンネル削除
- **環境変数の橋渡し (config.js 自動生成)**
  - ビルドツールを使わない構成のため、`.env` の内容を `npm run generate-config` で
    ブラウザから参照可能な `config.js` (`window.ENV`) に変換
  - `.env` / `config.js` は Git 管理対象外 (`.gitignore`)

## 前提条件

- Node.js (npm が使えること)
- `live-control-plane` (Rails API) がローカルで起動していること
  - チャンネルの作成・一覧取得・公開設定切り替え・配信停止はすべてこの API 経由で行うため必須
  - デフォルトで `3000` 番ポートで起動する想定 (詳細はリポジトリ直下の `live-control-plane/README.md` を参照)
- 通信品質チェック用に、誰でも GET/PUT できるパブリック S3 バケットを用意し、
  直下にダウンロード計測用のダミーファイル (`dummy_300mb.txt` など) を配置しておくこと
- Amazon IVS のチャンネルは `live-control-plane` 経由で作成するため、事前に個別作成する必要はない

## 動作手順

1. 依存パッケージのインストール

   ```bash
   npm install
   ```

2. 環境変数ファイルの作成

   `.env.example` を参考に `frontend/.env` を作成する。

   ```bash
   cp .env.example .env
   ```

   ```
   # live-control-plane (Rails API) のベースURL
   # 配信用のingest endpoint/stream keyはチャネル作成・選択時にこのAPI経由で取得するため、
   # ここでは直接指定しない
   API_BASE_URL=http://localhost:3000

   # 配信前の通信品質チェック用。誰でもGET/PUTできるパブリックS3バケットのベースURL
   BUCKET_BASE_URL=https://xxxxxx.s3.ap-northeast-1.amazonaws.com
   ```

   | 変数名 | 用途 |
   | --- | --- |
   | `API_BASE_URL` | `live-control-plane` のベースURL。チャンネルのCRUD・公開設定・配信停止・再生情報 (`.m3u8` / 再生トークン) の取得すべてに使用 |
   | `BUCKET_BASE_URL` | 通信品質チェックで直接GET/PUTするパブリックS3バケットのベースURL |

   `live-control-plane` はデフォルトで `3000` 番ポートを使用するため、このフロントエンドは
   **別のポート** (例: `5500`) で配信すること (手順4を参照)。

3. `config.js` の生成

   `.env` の内容から、ブラウザ側で読み込む `config.js` を生成する。
   `.env` を編集するたびに再実行する。

   ```bash
   npm run generate-config
   ```

4. `live-control-plane` を起動

   別ターミナルで `live-control-plane` ディレクトリに移動し、Rails サーバーを起動する
   (デフォルトで `http://localhost:3000`)。フロントエンドからの CORS アクセスが
   許可されるよう、`live-control-plane` 側の許可オリジン設定も確認すること。

5. 静的ファイルをローカルサーバーで配信

   `index.html` は ES Modules (`<script type="module">`) やカメラ/マイクの
   `getUserMedia` を使用するため、`file://` で直接開くのではなく、
   ローカル HTTP サーバー経由 (`http://localhost` など) で開く。
   `live-control-plane` が `3000` 番を使うため、**別のポート**を指定する。

   ```bash
   npx serve -l 5500
   ```

6. ブラウザでアクセスして動作確認

   `http://localhost:5500` を開く。

   - **通信品質チェック**: 「通信速度をチェック」ボタンをクリックすると、S3への
     ダウンロード/アップロードで回線速度を計測し、対応可能な画質を表示する
   - **配信側**: チャンネルを新規作成 (または一覧から選択) し、「配信開始」ボタンを
     クリックするとカメラ/マイクの使用許可を求められ、許可後に IVS への配信が始まる
     (プレビューは canvas に表示される)。公開設定の切り替えや配信停止も可能
   - **視聴側**: チャンネルを選択し「視聴開始」ボタンをクリックすると再生が始まる。
     画質は手動選択または自動 (ABR) に切り替え可能
   - **運営者**: 「一覧を更新」で全チャンネルを確認し、強制配信停止・削除ができる

## トラブルシューティング

- `.env が見つかりません` と表示される場合: 手順 2 で `frontend/.env` を作成する
- チャンネル一覧の取得やチャンネル作成に失敗する場合: `live-control-plane` が起動しているか、
  `API_BASE_URL` の値が正しいか、CORS 設定 (許可オリジン) を確認する
- カメラ/マイクが起動しない場合: ブラウザの権限設定、および `http://localhost` や
  `https://` などのセキュアコンテキストで開いているかを確認する
- 通信品質チェックが失敗する場合: `BUCKET_BASE_URL` のバケットが誰でも GET/PUT できる設定に
  なっているか、`dummy_300mb.txt` が配置されているかを確認する
- 配信/再生に失敗する場合: ブラウザのコンソールログと選択中チャンネルの設定値
  (ingest endpoint / stream key / playback URL) を確認する
