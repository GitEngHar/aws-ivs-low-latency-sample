// Amazon IVS Web Broadcast SDK は index.html の <script> タグでCDNから読み込み、
// グローバル変数 IVSBroadcastClient として公開される
const AmazonIVSBroadcastClient = window.IVSBroadcastClient;

// frontend/.env (config.jsとして生成) から取得
const INGEST_ENDPOINT = window.ENV.BROADCAST_INGEST_ENDPOINT;
const STREAM_KEY = window.ENV.BROADCAST_STREAM_KEY;

let client = null;
let mediaStream = null;

// 選択中の解像度プリセットでクライアントを作り直し、プレビューとデバイスを再設定する
// （streamConfigはクライアント生成時にしか指定できないため、プリセット変更のたびに作り直す）
async function setupClient(presetKey) {
    if (client) {
        client.delete();
    }

    client = AmazonIVSBroadcastClient.create({
        streamConfig: AmazonIVSBroadcastClient[presetKey],
    });

    // HTMLのcanvas要素に配信プレビューを表示
    const previewCanvas = document.getElementById('preview');
    client.attachPreview(previewCanvas);

    // カメラとマイクの取得（初回のみ）
    if (!mediaStream) {
        mediaStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    }

    // トラックの追加（addVideoInputDevice/addAudioInputDeviceはMediaStreamを受け取る）
    client.addVideoInputDevice(mediaStream, 'camera', { index: 0 });
    client.addAudioInputDevice(mediaStream, 'microphone');
}

async function initBroadcast() {
    const presetSelect = document.getElementById('preset-select');

    await setupClient(presetSelect.value);

    // プリセットを変更したらクライアントを作り直す
    presetSelect.addEventListener('change', () => {
        setupClient(presetSelect.value).catch(console.error);
    });

    // ボタンをクリックしたら配信スタート
    document.getElementById('start-btn').addEventListener('click', async () => {
        try {
            presetSelect.disabled = true;
            await client.startBroadcast(STREAM_KEY, INGEST_ENDPOINT);
            console.log('配信が開始されました！');
        } catch (error) {
            presetSelect.disabled = false;
            console.error('配信の開始に失敗しました:', error);
        }
    });
}

initBroadcast().catch(console.error);
