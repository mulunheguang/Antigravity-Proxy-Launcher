#!/usr/bin/env node
/** 打包前确认随扩展分发的 macOS 二进制已放入扩展的 bin/。 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const required = ['antigravity-relay', 'libantigravity.dylib'];

let ok = true;
for (const name of required) {
    const f = path.join(root, 'bin', name);
    if (!fs.existsSync(f)) {
        console.error(`缺少 ${f}`);
        ok = false;
        continue;
    }
    try {
        fs.accessSync(f, fs.constants.X_OK);
    } catch {
        console.error(`不可执行: ${f}（请 chmod +x）`);
        ok = false;
    }
}

if (!ok) {
    console.error('\n请在仓库根目录运行 make build，然后将 bin/ 中的两个二进制复制到 vscode-extension/bin/');
    process.exit(1);
}

console.log('bin 检查通过:', required.join(', '));
