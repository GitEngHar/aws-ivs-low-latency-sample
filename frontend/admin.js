import { adminListChannels, adminStopStream, adminDeleteChannel } from './api-client.js';

const refreshBtn = document.getElementById('admin-refresh-btn');
const tbody = document.getElementById('admin-channel-tbody');
const statusEl = document.getElementById('admin-status');

function showStatus(message) {
    statusEl.textContent = message;
}

function renderRow(channel) {
    const tr = document.createElement('tr');

    const nameTd = document.createElement('td');
    nameTd.textContent = channel.name || channel.arn;
    tr.appendChild(nameTd);

    const ownerTd = document.createElement('td');
    ownerTd.textContent = channel.user_id;
    tr.appendChild(ownerTd);

    const visibilityTd = document.createElement('td');
    visibilityTd.textContent = channel.authorized ? 'プライベート' : 'パブリック';
    tr.appendChild(visibilityTd);

    const actionsTd = document.createElement('td');

    const stopBtn = document.createElement('button');
    stopBtn.textContent = '配信停止';
    stopBtn.addEventListener('click', async () => {
        stopBtn.disabled = true;
        showStatus('');
        try {
            await adminStopStream(channel.id);
            showStatus(`チャネル「${channel.name || channel.arn}」の配信を停止しました`);
        } catch (error) {
            showStatus(`配信停止に失敗しました: ${error.message}`);
        } finally {
            stopBtn.disabled = false;
        }
    });
    actionsTd.appendChild(stopBtn);

    const deleteBtn = document.createElement('button');
    deleteBtn.textContent = '削除';
    deleteBtn.addEventListener('click', async () => {
        if (!window.confirm(`チャネル「${channel.name || channel.arn}」を削除します。よろしいですか？`)) {
            return;
        }
        deleteBtn.disabled = true;
        showStatus('');
        try {
            await adminDeleteChannel(channel.id);
            showStatus(`チャネル「${channel.name || channel.arn}」を削除しました`);
            await refreshChannelTable();
        } catch (error) {
            showStatus(`削除に失敗しました: ${error.message}`);
            deleteBtn.disabled = false;
        }
    });
    actionsTd.appendChild(deleteBtn);

    tr.appendChild(actionsTd);
    return tr;
}

async function refreshChannelTable() {
    tbody.innerHTML = '';

    let channels = [];
    try {
        channels = await adminListChannels();
    } catch (error) {
        showStatus(`チャネル一覧の取得に失敗しました: ${error.message}`);
        tbody.innerHTML = '<tr><td colspan="4">取得に失敗しました</td></tr>';
        return;
    }

    if (channels.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4">チャネルがありません</td></tr>';
        return;
    }

    for (const channel of channels) {
        tbody.appendChild(renderRow(channel));
    }
}

function initAdmin() {
    refreshBtn.addEventListener('click', () => refreshChannelTable());
    refreshChannelTable();
}

initAdmin();
