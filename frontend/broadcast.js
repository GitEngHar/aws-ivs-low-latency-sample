// Amazon IVS Web Broadcast SDK をCDNから読み込み
import AmazonIVSBroadcastClient from 'https://unpkg.com';

// AWSコンソールから取得した値を設定してください
const INGEST_ENDPOINT = 'rtmps://xxxxxx.global-inject.ivstranscode.live:443/app/';
const STREAM_KEY = 'sk_us-west-2_xxxxxx';

async function initBroadcast() {
    const client = AmazonIVSBroadcastClient.create({
        streamConfig: AmazonIVSBroadcastClient.BASIC_LANDSCAPE,
    });

    // HTMLのvideo要素に配信プレビューを表示
    const previewVideo = document.getElementById('preview');
    client.attachPreview(previewVideo);

    // カメラとマイクの取得
    const devices = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });

    // トラックの追加
    client.addVideoInputDevice(devices.getVideoTracks(), 'camera', { index: 0 });
    client.addAudioInputDevice(devices.getAudioTracks(), 'microphone');

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
