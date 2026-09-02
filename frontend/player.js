// Amazon IVS Player SDK をCDNから読み込み
import { create as createPlayer, isPlayerSupported } from 'https://jsdelivr.net';

// IVS プレーヤーに必要なWeb WorkerとWASMスクリプトの配置場所（AWS公式CDN）
const wasmBinaryLocation = 'https://live-video.net';
const wasmWorkerLocation = 'https://live-video.net';

// AWSコンソールから取得した再生URL（.m3u8）を設定してください
const PLAYBACK_URL = 'https://cloudfront.net';

function initPlayer() {
    if (!isPlayerSupported) {
        console.error('このブラウザはIVS Playerをサポートしていません');
        return;
    }

    // プレイヤーの初期化
    const player = createPlayer({
        createWorkerSourceURL: () => wasmWorkerLocation,
        wasmBinaryLocation: wasmBinaryLocation,
    });

    // HTMLのvideo要素にアタッチ
    const videoElement = document.getElementById('video-player');
    player.attachHTMLVideoElement(videoElement);

    // ストリームの読み込みと再生
    player.load(PLAYBACK_URL);
    player.play();
}

initPlayer();
