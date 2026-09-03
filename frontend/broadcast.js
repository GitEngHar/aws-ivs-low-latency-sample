import { createChannel, listChannels, getChannel, setChannelVisibility, stopOwnStream } from './api-client.js';

// Amazon IVS Web Broadcast SDK は index.html の <script> タグでCDNから読み込み、
// グローバル変数 IVSBroadcastClient として公開される
const AmazonIVSBroadcastClient = window.IVSBroadcastClient;

const channelSelect = document.getElementById('channel-select');
const createChannelBtn = document.getElementById('create-channel-btn');
const presetSelect = document.getElementById('preset-select');
const startBtn = document.getElementById('start-btn');
const stopBroadcastBtn = document.getElementById('stop-broadcast-btn');
const visibilityToggleBtn = document.getElementById('visibility-toggle-btn');
const statusEl = document.getElementById('broadcast-status');

let client = null;
let mediaStream = null;
let selectedChannel = null; // 選択中のチャネル（stream_key_value込みの詳細）
let isBroadcasting = false;

function showStatus(message) {
    statusEl.textContent = message;
}

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

function updateVisibilityButtonLabel() {
    if (!selectedChannel) {
        visibilityToggleBtn.textContent = 'プライベートに切替';
        return;
    }
    visibilityToggleBtn.textContent = selectedChannel.authorized ? 'パブリックに切替' : 'プライベートに切替';
}

// 配信中/チャネル未選択などの状態に応じて各コントロールの活性・非活性を揃える
function updateBroadcastControlsState() {
    const hasChannel = !!selectedChannel;
    channelSelect.disabled = isBroadcasting;
    createChannelBtn.disabled = isBroadcasting;
    presetSelect.disabled = isBroadcasting;
    startBtn.disabled = !hasChannel || isBroadcasting;
    stopBroadcastBtn.disabled = !isBroadcasting;
    visibilityToggleBtn.disabled = !hasChannel;
}

// 公開設定の切り替え中は誤操作を防ぐため全コントロールを一時的にロックする
function setControlsDisabled(disabled) {
    channelSelect.disabled = disabled;
    createChannelBtn.disabled = disabled;
    presetSelect.disabled = disabled;
    startBtn.disabled = disabled;
    stopBroadcastBtn.disabled = disabled;
    visibilityToggleBtn.disabled = disabled;
}

async function selectChannel(channelId) {
    if (!channelId) {
        selectedChannel = null;
        updateVisibilityButtonLabel();
        updateBroadcastControlsState();
        return;
    }

    try {
        selectedChannel = await getChannel(channelId);
    } catch (error) {
        selectedChannel = null;
        showStatus(`チャネル情報の取得に失敗しました: ${error.message}`);
    }

    updateVisibilityButtonLabel();
    updateBroadcastControlsState();
}

// チャネル一覧を取得して<select>を再構築する。preferredChannelIdがあれば優先的に選択する
async function refreshChannelList(preferredChannelId) {
    channelSelect.innerHTML = '';

    let channels = [];
    try {
        channels = await listChannels();
    } catch (error) {
        showStatus(`チャネル一覧の取得に失敗しました: ${error.message}`);
    }

    if (channels.length === 0) {
        const option = document.createElement('option');
        option.value = '';
        option.textContent = 'チャネルがありません（新規作成してください）';
        channelSelect.appendChild(option);
        await selectChannel(null);
        return;
    }

    for (const channel of channels) {
        const option = document.createElement('option');
        option.value = channel.id;
        option.textContent = `${channel.name || channel.arn} (${channel.authorized ? 'プライベート' : 'パブリック'})`;
        channelSelect.appendChild(option);
    }

    const hasPreferred = preferredChannelId != null
        && channels.some((channel) => String(channel.id) === String(preferredChannelId));
    const targetId = hasPreferred ? preferredChannelId : channels[0].id;

    channelSelect.value = String(targetId);
    await selectChannel(targetId);
}

// 配信を停止し、公開設定を切り替えたのち、配信中だった場合は自動的に再開する
async function onToggleVisibility() {
    if (!selectedChannel) {
        return;
    }

    const wasBroadcasting = isBroadcasting;
    const targetAuthorized = !selectedChannel.authorized;

    showStatus('');
    setControlsDisabled(true);

    try {
        if (wasBroadcasting) {
            client.stopBroadcast();
            isBroadcasting = false;
        }

        const updated = await setChannelVisibility(selectedChannel.id, targetAuthorized);
        selectedChannel.authorized = updated.authorized;
        updateVisibilityButtonLabel();

        if (wasBroadcasting) {
            await client.startBroadcast(selectedChannel.stream_key_value, selectedChannel.ingest_endpoint);
            isBroadcasting = true;
        }
    } catch (error) {
        showStatus(`公開設定の切り替えに失敗しました: ${error.message}`);
    } finally {
        updateBroadcastControlsState();
    }
}

// ローカルのエンコーダー(自分のカメラ/マイク送出)を止め、IVS側のRTMPSセッションも切断する
async function onStopBroadcast() {
    if (!isBroadcasting || !selectedChannel) {
        return;
    }

    showStatus('');
    setControlsDisabled(true);

    try {
        client.stopBroadcast();
        isBroadcasting = false;
        await stopOwnStream(selectedChannel.id);
    } catch (error) {
        showStatus(`配信停止に失敗しました: ${error.message}`);
    } finally {
        updateBroadcastControlsState();
    }
}

async function initBroadcast() {
    await setupClient(presetSelect.value);

    // プリセットを変更したらクライアントを作り直す
    presetSelect.addEventListener('change', () => {
        setupClient(presetSelect.value).catch(console.error);
    });

    await refreshChannelList();

    // チャネルを選択したら配信に使う情報を取得し直す
    channelSelect.addEventListener('change', () => {
        selectChannel(channelSelect.value);
    });

    // 新規チャネル作成
    createChannelBtn.addEventListener('click', async () => {
        createChannelBtn.disabled = true;
        showStatus('');
        try {
            const channel = await createChannel();
            await refreshChannelList(channel.id);
        } catch (error) {
            showStatus(`チャネル作成に失敗しました: ${error.message}`);
        } finally {
            updateBroadcastControlsState();
        }
    });

    // ボタンをクリックしたら配信スタート（選択中チャネルのstream_key/ingest_endpointを使用）
    startBtn.addEventListener('click', async () => {
        if (!selectedChannel) {
            return;
        }
        showStatus('');
        try {
            await client.startBroadcast(selectedChannel.stream_key_value, selectedChannel.ingest_endpoint);
            isBroadcasting = true;
            console.log('配信が開始されました！');
        } catch (error) {
            showStatus(`配信の開始に失敗しました: ${error.message}`);
            console.error('配信の開始に失敗しました:', error);
        } finally {
            updateBroadcastControlsState();
        }
    });

    // 配信停止
    stopBroadcastBtn.addEventListener('click', onStopBroadcast);

    // パブリック/プライベート切替
    visibilityToggleBtn.addEventListener('click', onToggleVisibility);
}

initBroadcast().catch(console.error);
