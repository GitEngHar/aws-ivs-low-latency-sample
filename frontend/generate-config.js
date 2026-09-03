// .env を読み込み、ブラウザから参照可能な config.js (window.ENV) を生成する
// ビルドツールを使わない静的配信構成のため、この簡易スクリプトで .env を橋渡しする
const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '.env');
const outPath = path.join(__dirname, 'config.js');

if (!fs.existsSync(envPath)) {
    console.error('.env が見つかりません。.env.example を参考に frontend/.env を作成してください。');
    process.exit(1);
}

const env = {};
for (const line of fs.readFileSync(envPath, 'utf-8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;
    env[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
}

const body = `// このファイルは frontend/.env から自動生成されます。直接編集しないでください。
// 再生成: npm run generate-config
window.ENV = ${JSON.stringify(env, null, 4)};
`;

fs.writeFileSync(outPath, body);
console.log(`config.js を生成しました (${Object.keys(env).length} 件の環境変数)`);
