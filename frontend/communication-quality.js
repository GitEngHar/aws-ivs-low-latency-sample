// 配信前 通信品質チェック
// バックエンド(live-control-plane)は一切経由せず、ブラウザから直接S3(公開バケット)へ
// GET/PUTして回線速度を計測する。計測対象がRailsサーバーの回線になってしまっては
// 意味がないため、この機能はフロントエンド完結で実装している。

const BUCKET_BASE_URL = window.ENV.BUCKET_BASE_URL;
const DOWNLOAD_URL = `${BUCKET_BASE_URL}/dummy_300mb.txt`;
const UPLOAD_KEY_PREFIX = 'communication-quality-checks';

// アップロード計測用のダミーペイロードサイズ。小さすぎるとTCP/TLSハンドシェイクの
// オーバーヘッドで速度が不正確になり、大きすぎると低速回線での待ち時間が伸びるためのバランス値。
const UPLOAD_PAYLOAD_BYTES = 5 * 1024 * 1024; // 5MB

// 各画質を安定して配信するためのエンコーダー想定アップロードビットレート。
const TARGET_ENCODE_BITRATE_MBPS = { '1080p': 4.5, '720p': 3.0, '480p': 1.5 };
// 上記に掛けるヘッドルーム（安全マージン）。回線の揺らぎを吸収するため実測がこれを
// 上回って初めて「対応可能」と判定する。
const HEADROOM_MULTIPLIER = 1.3;
// 高画質から順に評価し、最初に条件を満たした画質を推奨とする。
const TIERS_HIGHEST_FIRST = ['1080p', '720p', '480p'];

const checkBtn = document.getElementById('quality-check-btn');
const statusEl = document.getElementById('quality-check-status');
const resultEl = document.getElementById('quality-check-result');

function requiredMbps(tier) {
    return TARGET_ENCODE_BITRATE_MBPS[tier] * HEADROOM_MULTIPLIER;
}

// 実測アップロード速度(Mbps)から、画質ごとの対応可否と推奨画質を判定する
function evaluateQuality(uploadMbps) {
    const tiers = {};
    let recommendedQuality = null;

    for (const tier of TIERS_HIGHEST_FIRST) {
        tiers[tier] = uploadMbps >= requiredMbps(tier);
        if (tiers[tier] && recommendedQuality === null) {
            recommendedQuality = tier;
        }
    }

    return { tiers, recommendedQuality, streamingRecommended: recommendedQuality !== null };
}

function bytesToMbps(bytes, durationMs) {
    return (bytes * 8) / (durationMs / 1000) / 1_000_000;
}

// DOWNLOAD_URLへ直接fetchし、実際に受信したバイト数と所要時間を計測する
async function measureDownload() {
    const start = performance.now();
    const response = await fetch(DOWNLOAD_URL, { cache: 'no-store' });

    if (!response.ok) {
        throw new Error(`ダウンロード計測に失敗しました (status: ${response.status})`);
    }

    let bytes = 0;
    const reader = response.body.getReader();
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        bytes += value.length;
    }

    return { bytes, durationMs: performance.now() - start };
}

// バケット内のユニークなキーへ直接ダミーペイロードをPUTし、所要時間を計測する
// （バケットポリシーで誰でもPutObject可能なため、署名やAPI呼び出しは不要）
async function measureUpload() {
    const key = `${UPLOAD_KEY_PREFIX}/${crypto.randomUUID()}.bin`;
    const payload = new Uint8Array(UPLOAD_PAYLOAD_BYTES);

    const start = performance.now();
    const response = await fetch(`${BUCKET_BASE_URL}/${key}`, { method: 'PUT', body: payload, cache: 'no-store' });
    const durationMs = performance.now() - start;

    if (!response.ok) {
        throw new Error(`アップロード計測に失敗しました (status: ${response.status})`);
    }

    return { bytes: payload.byteLength, durationMs };
}

function renderResult({ downloadMbps, uploadMbps, tiers, recommendedQuality, streamingRecommended }) {
    const tierRows = TIERS_HIGHEST_FIRST
        .map((tier) => `<li>${tier}: ${tiers[tier] ? '✅ 対応可能' : '❌ 力不足'}</li>`)
        .join('');

    const conclusion = streamingRecommended
        ? `推奨画質: <strong>${recommendedQuality}</strong>`
        : '<strong>配信非推奨</strong>: 現在の回線ではいずれの画質も安定して配信できません';

    resultEl.innerHTML = `
        <p>ダウンロード速度: ${downloadMbps.toFixed(2)} Mbps</p>
        <p>アップロード速度: ${uploadMbps.toFixed(2)} Mbps</p>
        <ul>${tierRows}</ul>
        <p>${conclusion}</p>
    `;
}

async function runCommunicationQualityCheck() {
    checkBtn.disabled = true;
    resultEl.innerHTML = '';

    try {
        statusEl.textContent = 'ダウンロード速度を計測中...（300MBのダウンロードのため回線が遅い場合は時間がかかります）';
        const download = await measureDownload();

        statusEl.textContent = 'アップロード速度を計測中...';
        const upload = await measureUpload();

        const downloadMbps = bytesToMbps(download.bytes, download.durationMs);
        const uploadMbps = bytesToMbps(upload.bytes, upload.durationMs);
        const verdict = evaluateQuality(uploadMbps);

        statusEl.textContent = '';
        renderResult({ downloadMbps, uploadMbps, ...verdict });
    } catch (error) {
        statusEl.textContent = `通信品質チェックに失敗しました: ${error.message}`;
    } finally {
        checkBtn.disabled = false;
    }
}

checkBtn.addEventListener('click', runCommunicationQualityCheck);
