import { listChannels, getChannel, getPlaybackToken } from './api-client.js';

// Amazon IVS Player SDK は index.html の <script> タグでCDNから読み込み、
// グローバル変数 IVSPlayer として公開される
const { create: createPlayer, isPlayerSupported, PlayerState, PlayerEventType } = window.IVSPlayer;

// mock: プライベートチャネルのトークン更新をデモとして無限に繰り返さないよう、上限を設ける
const MAX_TOKEN_REFRESHES = 3;

// トークン失効ちょうどで再生が止まらないよう、期限の少し手前で更新する
const TOKEN_REFRESH_MARGIN_MS = 5000;

const channelSelect = document.getElementById('watch-channel-select');
const watchBtn = document.getElementById('watch-btn');
const qualitySelect = document.getElementById('quality-select');
const statusEl = document.getElementById('watch-status');

const AUTO_QUALITY_VALUE = 'auto';

let player = null;
let selectedChannel = null;
let refreshTimer = null;
let refreshCount = 0;

function showStatus(message) {
    statusEl.textContent = message;
}

// トークンの署名は検証せず、更新タイミングを決めるためだけに exp (Unix秒) を読み取る
function decodeTokenExp(token) {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return payload.exp;
}

function clearScheduledRefresh() {
    clearTimeout(refreshTimer);
    refreshTimer = null;
}

// 新しいソースを読み込む間、直前のチャネルの画質選択肢を表示したままにしない
function resetQualitySelect() {
    qualitySelect.innerHTML = '';
    const option = document.createElement('option');
    option.value = '';
    option.textContent = '画質を読み込み中...';
    qualitySelect.appendChild(option);
    qualitySelect.disabled = true;
}

// READY到達時に取得できる画質一覧から<select>を組み立てる。「自動(ABR)」も選択肢として残す
function populateQualityOptions(qualities) {
    qualitySelect.innerHTML = '';

    const autoOption = document.createElement('option');
    autoOption.value = AUTO_QUALITY_VALUE;
    autoOption.textContent = '自動 (ABR)';
    qualitySelect.appendChild(autoOption);

    for (const quality of qualities) {
        const option = document.createElement('option');
        option.value = quality.name;
        const resolution = quality.height ? `${quality.height}p / ` : '';
        option.textContent = `${quality.name} (${resolution}${Math.round(quality.bitrate / 1000)}kbps)`;
        qualitySelect.appendChild(option);
    }

    qualitySelect.disabled = false;
}

// 現在の再生画質(または自動モード中であること)を<select>の表示に反映する
function syncQualitySelectValue() {
    if (player.isAutoQualityMode()) {
        qualitySelect.value = AUTO_QUALITY_VALUE;
        return;
    }

    const current = player.getQuality();
    if (current) {
        qualitySelect.value = current.name;
    }
}

// プライベートチャネル視聴中、トークンの期限が近づいたら再取得してプレイヤーを再読み込みする
// mock: 更新回数は MAX_TOKEN_REFRESHES 回までとし、それ以降は期限切れのまま視聴を継続させる
function scheduleTokenRefresh(channel, token) {
    clearScheduledRefresh();

    if (refreshCount >= MAX_TOKEN_REFRESHES) {
        showStatus(`トークン更新の上限（${MAX_TOKEN_REFRESHES}回）に達しました。これ以降は再取得しません。`);
        return;
    }

    const expiresAtMs = decodeTokenExp(token) * 1000;
    const delay = Math.max(expiresAtMs - Date.now() - TOKEN_REFRESH_MARGIN_MS, 0);

    refreshTimer = setTimeout(async () => {
        refreshCount += 1;
        try {
            showStatus(`トークンを更新しています... (${refreshCount}/${MAX_TOKEN_REFRESHES}回目)`);
            await playChannel(channel);
        } catch (error) {
            showStatus(`トークンの更新に失敗しました: ${error.message}`);
        }
    }, delay);
}

// 選択中チャネルの再生を開始する。プライベートチャネルの場合はトークンを取得してURLに付与する
async function playChannel(channel) {
    resetQualitySelect();

    let playbackUrl = channel.playback_url;

    if (channel.authorized) {
        console.log("Private channel detected ...");
        const token = await getPlaybackToken(channel.id);
        playbackUrl = `${playbackUrl}?token=${encodeURIComponent(token)}`;
        scheduleTokenRefresh(channel, token);
    } else {
        clearScheduledRefresh();
    }

    player.load(playbackUrl);
    player.play();
}

async function selectChannel(channelId) {
    clearScheduledRefresh();
    refreshCount = 0;

    if (!channelId) {
        selectedChannel = null;
        watchBtn.disabled = true;
        return;
    }

    try {
        selectedChannel = await getChannel(channelId);
        watchBtn.disabled = false;
    } catch (error) {
        selectedChannel = null;
        watchBtn.disabled = true;
        showStatus(`チャネル情報の取得に失敗しました: ${error.message}`);
    }
}

// チャネル一覧を取得して<select>を再構築する
async function refreshChannelList() {
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
        option.textContent = 'チャネルがありません（配信側で作成してください）';
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

    channelSelect.value = String(channels[0].id);
    await selectChannel(channels[0].id);
}

function initPlayer() {
    if (!isPlayerSupported) {
        console.error('このブラウザはIVS Playerをサポートしていません');
        return;
    }

    player = createPlayer();
    player.attachHTMLVideoElement(document.getElementById('video-player'));

    // READYになった時点で選択可能な画質が揃う。自動画質変換(ABR)は既定でオフにし、
    // 直前まで再生していた画質のまま固定して、以降はユーザーの選択でのみ切り替える
    // （iOSブラウザ等、qualitiesが取得できない環境では自動モードのままにする）
    player.addEventListener(PlayerState.READY, () => {
        const qualities = player.getQualities();
        if (qualities.length === 0) {
            resetQualitySelect();
            return;
        }

        const current = player.getQuality();
        player.setAutoQualityMode(false);
        if (current) {
            player.setQuality(current, false);
        }

        populateQualityOptions(qualities);
        syncQualitySelectValue();
    });

    // ユーザー操作以外(自動モード中の内部切り替え等)による変化も<select>に反映する
    player.addEventListener(PlayerEventType.QUALITY_CHANGED, () => {
        syncQualitySelectValue();
    });

    qualitySelect.addEventListener('change', () => {
        if (qualitySelect.value === AUTO_QUALITY_VALUE) {
            player.setAutoQualityMode(true);
            return;
        }

        const quality = player.getQualities().find((q) => q.name === qualitySelect.value);
        if (quality) {
            player.setQuality(quality, false);
        }
    });

    channelSelect.addEventListener('change', () => {
        selectChannel(channelSelect.value);
    });

    watchBtn.addEventListener('click', async () => {
        if (!selectedChannel) {
            return;
        }
        showStatus('');
        refreshCount = 0;
        try {
            await playChannel(selectedChannel);
        } catch (error) {
            showStatus(`視聴の開始に失敗しました: ${error.message}`);
        }
    });

    refreshChannelList();
}

initPlayer();
