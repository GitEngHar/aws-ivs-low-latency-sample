// live-control-plane (Rails API) と通信する唯一の窓口
// mock user-idはFEで固定保持し、ユーザー紐付けが必要なリクエストに毎回付与する
export const MOCK_USER_ID = '91E28B83-6B21-4F6E-B000-5004DE0FBACF';

const API_BASE_URL = window.ENV.API_BASE_URL;

async function request(path, options = {}) {
    let response;
    try {
        response = await fetch(`${API_BASE_URL}${path}`, {
            ...options,
            headers: {
                'X-User-Id': MOCK_USER_ID,
                ...(options.body ? { 'Content-Type': 'application/json' } : {}),
                ...options.headers,
            },
        });
    } catch (error) {
        throw new Error(`APIへの接続に失敗しました: ${error.message}`);
    }

    const body = await response.json().catch(() => ({}));

    if (!response.ok) {
        throw new Error(body.error || `APIエラー (status: ${response.status})`);
    }

    return body;
}

export async function createChannel(name) {
    const body = await request('/live/streams/create', {
        method: 'POST',
        body: JSON.stringify({ name }),
    });
    return body.channel;
}

export async function listChannels() {
    const body = await request('/live/streams/list');
    return body.channels;
}

export async function getChannel(channelId) {
    const body = await request(`/live/streams/show?channel_id=${encodeURIComponent(channelId)}`);
    return body.channel;
}

export async function getPlaybackToken(channelId) {
    const body = await request(`/live/streams/playback_token?channel_id=${encodeURIComponent(channelId)}`);
    return body.playback_token;
}

export async function setChannelVisibility(channelId, authorized) {
    const path = authorized ? '/live/streams/change_to_private' : '/live/streams/change_to_public';
    const body = await request(path, {
        method: 'POST',
        body: JSON.stringify({ channel_id: channelId }),
    });
    return body.channel;
}

// 配信側: 自チャネルの配信を停止する
export async function stopOwnStream(channelId) {
    await request('/live/streams/stop_stream', {
        method: 'POST',
        body: JSON.stringify({ channel_id: channelId }),
    });
}

// 運営者: 所有者に関わらず全チャネルを取得する
export async function adminListChannels() {
    const body = await request('/admin/streams/list');
    return body.channels;
}

// 運営者: 所有者に関わらず配信を強制停止する
export async function adminStopStream(channelId) {
    await request('/admin/streams/stop_stream', {
        method: 'POST',
        body: JSON.stringify({ channel_id: channelId }),
    });
}

// 運営者: 所有者に関わらずチャネルを削除する（配信中なら強制停止してから削除）
export async function adminDeleteChannel(channelId) {
    await request('/admin/streams/destroy', {
        method: 'POST',
        body: JSON.stringify({ channel_id: channelId }),
    });
}
