// Amazon IVS Web Broadcast SDK は index.html の <script> タグでCDNから読み込み、
// グローバル変数 IVSBroadcastClient として公開される
const AmazonIVSBroadcastClient = window.IVSBroadcastClient;

// frontend/.env (config.jsとして生成) から取得
const INGEST_ENDPOINT = window.ENV.BROADCAST_INGEST_ENDPOINT;
const STREAM_KEY = window.ENV.BROADCAST_STREAM_KEY;

async function initBroadcast() {
    const client = AmazonIVSBroadcastClient.create({
        streamConfig: AmazonIVSBroadcastClient.BASIC_LANDSCAPE,
    });

    // HTMLのvideo要素に配信プレビューを表示
    const previewVideo = document.getElementById('preview');
    client.attachPreview(previewVideo);

    // カメラとマイクの取得
    const devices = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });

    // トラックの追加（addVideoInputDevice/addAudioInputDeviceはMediaStreamを受け取る）
    client.addVideoInputDevice(devices, 'camera', { index: 0 });
    client.addAudioInputDevice(devices, 'microphone');

    // ボタンをクリックしたら配信スタート
    document.getElementById('start-btn').addEventListener('click', async () => {
        try {
            await client.startBroadcast(STREAM_KEY, INGEST_ENDPOINT);
            console.log('配信が開始されました！');
        } catch (error) {
            console.error('配信の開始に失敗しました:', error);
        }
    });
}

initBroadcast().catch(console.error);
