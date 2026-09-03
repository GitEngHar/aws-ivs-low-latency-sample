# AWS IVS 低レイテンシー配信 & 視聴 デモ (frontend)

Amazon IVS (Interactive Video Service) の Web Broadcast SDK と Player SDK を使った、
ビルドツール不要の低レイテンシーライブ配信・視聴デモです。

## 機能一覧

- **配信 (Broadcast)**
  - カメラ・マイクを取得し、ブラウザからそのまま IVS へライブ配信
  - `canvas` 要素に配信プレビューを表示
  - ボタン操作で配信を開始 (`amazon-ivs-web-broadcast` SDK)
- **視聴 (Player)**
  - IVS のプレイバック URL (`.m3u8`) を `video` 要素で低遅延再生
  - ボタン操作で再生を開始 (`amazon-ivs-player` SDK)
  - ブラウザが未対応の場合はコンソールにエラーを出力
- **環境変数の橋渡し (config.js 自動生成)**
  - ビルドツールを使わない構成のため、`.env` の内容を `npm run generate-config` で
    ブラウザから参照可能な `config.js` (`window.ENV`) に変換
  - `.env` / `config.js` は Git 管理対象外 (`.gitignore`)

## 前提条件

- Node.js (npm が使えること)
- Amazon IVS のチャンネル (配信用エンドポイント/ストリームキー、視聴用プレイバック URL) が作成済みであること
  - AWS コンソールまたは `CreateChannel` API から取得

## 動作手順

1. 依存パッケージのインストール

   ```bash
   npm install
   ```

2. 環境変数ファイルの作成

   `.env.example` を参考に `frontend/.env` を作成し、IVS チャンネルの値を設定する。

   ```bash
   cp .env.example .env
   ```

   ```
   # 配信側 (ホスト名のみ。rtmps://やポート、パスは含めない)
   BROADCAST_INGEST_ENDPOINT=xxxxxx.global-contribute.live-video.net
   BROADCAST_STREAM_KEY=sk_us-west-2_xxxxxx

   # 視聴側の再生URL (.m3u8)
   PLAYBACK_URL=https://xxxxxx.ap-northeast-1.playback.live-video.net/api/video/v1/xxxxxx.m3u8
   ```

3. `config.js` の生成

   `.env` の内容から、ブラウザ側で読み込む `config.js` を生成する。
   `.env` を編集するたびに再実行する。

   ```bash
   npm run generate-config
   ```

4. 静的ファイルをローカルサーバーで配信

   `index.html` は ES Modules (`<script type="module">`) やカメラ/マイクの
   `getUserMedia` を使用するため、`file://` で直接開くのではなく、
   ローカル HTTP サーバー経由 (`http://localhost` など) で開く。

   ```bash
   npx serve -p 3001
   ```

5. ブラウザでアクセスして動作確認

   `http://localhost:3001` を開く。

   - **配信側**: 「配信開始」ボタンをクリックするとカメラ/マイクの使用許可を求められ、
     許可後に IVS への配信が始まる (プレビューは canvas に表示される)
   - **視聴側**: 「視聴開始」ボタンをクリックすると `PLAYBACK_URL` の映像が再生される

## トラブルシューティング

- `.env が見つかりません` と表示される場合: 手順 2 で `frontend/.env` を作成する
- カメラ/マイクが起動しない場合: ブラウザの権限設定、および `http://localhost` や
  `https://` などのセキュアコンテキストで開いているかを確認する
- 配信/再生に失敗する場合: ブラウザのコンソールログとIVSチャンネルの設定値 (エンドポイント/
  ストリームキー/プレイバックURL) を確認する
