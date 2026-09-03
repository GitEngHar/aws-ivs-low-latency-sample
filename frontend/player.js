// Amazon IVS Player SDK は index.html の <script> タグでCDNから読み込み、
// グローバル変数 IVSPlayer として公開される
const { create: createPlayer, isPlayerSupported } = window.IVSPlayer;

// frontend/.env (config.jsとして生成) から取得
const PLAYBACK_URL = window.ENV.PLAYBACK_URL;

function initPlayer() {
    if (!isPlayerSupported) {
        console.error('このブラウザはIVS Playerをサポートしていません');
        return;
    }

    // プレイヤーの初期化
    // ※ wasmWorkerLocation/wasmBinaryLocationはnpm経由での利用時のみ必要なオプションのため、
    //   CDNのscriptタグ経由では指定不要（SDKが自身のCDNパスを内部で解決する）
    const player = createPlayer();

    // HTMLのvideo要素にアタッチ
    const videoElement = document.getElementById('video-player');
    player.attachHTMLVideoElement(videoElement);

    // ボタンをクリックしたら視聴スタート
    document.getElementById('watch-btn').addEventListener('click', () => {
        player.load(PLAYBACK_URL);
        player.play();
    });
}

initPlayer();
