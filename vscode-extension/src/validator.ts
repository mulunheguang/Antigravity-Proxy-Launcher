import * as net from 'net';
import * as path from 'path';
import { resolveAntigravityExecutable } from './antigravityApp';
import { log, logError, logSuccess } from './logger';
import { ProxyConfig } from './configManager';

export interface ValidationResult {
    field: string;
    valid: boolean;
    message: string;
}

export const SOCKS5_REQUIRED = '注入库与 SNI 中继需要无认证 SOCKS5。请填写本地 SOCKS5 监听端口，并将类型设为 SOCKS5。';

/**
 * 校验代理连通性：尝试 TCP 连接 host:port
 */
export async function validateProxyConnection(
    host: string,
    port: number,
    timeoutMs: number = 3000
): Promise<ValidationResult> {
    return new Promise((resolve) => {
        const socket = new net.Socket();
        const timeout = Math.min(Math.max(timeoutMs, 500), 60000);

        socket.setTimeout(timeout);

        socket.on('connect', () => {
            socket.destroy();
            logSuccess(`代理连通性检测通过: ${host}:${port}`);
            resolve({ field: 'proxy', valid: true, message: `✅ 代理 ${host}:${port} TCP 连通` });
        });

        socket.on('timeout', () => {
            socket.destroy();
            logError(`代理连接超时: ${host}:${port}`);
            resolve({ field: 'proxy', valid: false, message: `❌ 连接超时 (${timeout}ms)` });
        });

        socket.on('error', (err) => {
            socket.destroy();
            logError(`代理连接失败: ${err.message}`);
            resolve({ field: 'proxy', valid: false, message: `❌ 连接失败: ${err.message}` });
        });

        socket.connect(port, host);
    });
}

/**
 * SOCKS5 无认证握手：发送 VER/NMETHODS，期望 0x05 0x00
 */
export async function validateSocks5Handshake(
    host: string,
    port: number,
    timeoutMs: number = 3000
): Promise<ValidationResult> {
    return new Promise((resolve) => {
        const socket = new net.Socket();
        const timeout = Math.min(Math.max(timeoutMs, 500), 60000);
        const finish = (valid: boolean, message: string) => {
            socket.destroy();
            resolve({ field: 'proxy_socks5', valid, message });
        };

        socket.setTimeout(timeout);

        socket.once('connect', () => {
            socket.write(Buffer.from([0x05, 0x01, 0x00]));
        });

        socket.once('timeout', () => {
            logError(`SOCKS5 握手超时: ${host}:${port}`);
            finish(false, `❌ SOCKS5 握手超时 (${timeout}ms)`);
        });

        socket.once('error', (err) => {
            logError(`SOCKS5 握手失败: ${err.message}`);
            finish(false, `❌ SOCKS5 握手失败: ${err.message}`);
        });

        socket.once('end', () => finish(false, '❌ 代理在 SOCKS5 协商完成前关闭了连接'));

        let response = Buffer.alloc(0);
        socket.on('data', (data: Buffer) => {
            response = Buffer.concat([response, data.subarray(0, 2 - response.length)]);
            if (response.length < 2) {
                return;
            }
            if (response[0] === 0x05 && response[1] === 0x00) {
                logSuccess(`SOCKS5 握手成功: ${host}:${port}`);
                finish(true, '✅ SOCKS5 无认证协商成功（握手检测）');
            } else {
                const preview = response.toString('hex');
                finish(false, `❌ 非法 SOCKS5 应答: ${preview}`);
            }
        });

        socket.connect(port, host);
    });
}

export async function validateUpstreamProtocol(config: ProxyConfig): Promise<ValidationResult> {
    if (config.type !== 'socks5') {
        return { field: 'proxy_socks5', valid: false, message: `❌ ${SOCKS5_REQUIRED}` };
    }
    const address = validateHost(config.host);
    if (!address.valid) {
        return address;
    }
    const port = validatePort(config.port);
    if (!port.valid) {
        return port;
    }
    return validateSocks5Handshake(config.host, config.port, config.timeout || 5000);
}

/**
 * 校验端口合法性
 */
export function validatePort(port: number): ValidationResult {
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
        return { field: 'port', valid: false, message: '❌ 端口应为 1-65535 的整数' };
    }
    return { field: 'port', valid: true, message: '✅ 端口格式正确' };
}

/**
 * 校验 IP 或域名格式
 */
export function validateHost(host: string): ValidationResult {
    if (!host || host.trim().length === 0) {
        return { field: 'host', valid: false, message: '❌ 代理地址不能为空' };
    }
    // IPv4
    const ipv4 = /^(\d{1,3}\.){3}\d{1,3}$/;
    // 域名
    const domain = /^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$/;

    if (ipv4.test(host)) {
        const parts = host.split('.').map(Number);
        if (parts.every(p => p >= 0 && p <= 255)) {
            return { field: 'host', valid: true, message: '✅ IP 地址格式正确' };
        }
        return { field: 'host', valid: false, message: '❌ IP 地址各段应为 0-255' };
    }

    if (domain.test(host)) {
        return { field: 'host', valid: true, message: '✅ 域名格式正确' };
    }

    if (host === 'localhost') {
        return { field: 'host', valid: true, message: '✅ localhost' };
    }

    return { field: 'host', valid: false, message: '❌ 地址格式不正确' };
}

/**
 * 自动检测 Antigravity.app 路径
 */
export function detectAntigravityPath(): string | null {
    const executable = resolveAntigravityExecutable('');
    if (executable) {
        const bundle = path.resolve(executable, '../../..');
        log(`自动检测到 Antigravity: ${bundle}`);
        return bundle;
    }
    return null;
}

/**
 * 校验 Antigravity.app 路径
 */
export function validateAntigravityPath(appPath: string): ValidationResult {
    const executable = resolveAntigravityExecutable(appPath);
    const message = executable
        ? `✅ 主程序: ${executable}`
        : appPath.trim()
            ? '❌ 该路径不是有效的 Antigravity.app（请检查 Info.plist 和主程序的执行权限）'
            : '❌ 未找到 Antigravity.app，请手动指定路径';
    return { field: 'antigravityAppPath', valid: Boolean(executable), message };
}

/**
 * 执行全量校验
 */
export async function validateAll(config: ProxyConfig): Promise<ValidationResult[]> {
    const results: ValidationResult[] = [];

    const host = validateHost(config.host);
    const port = validatePort(config.port);
    results.push(host, port);

    results.push(validateAntigravityPath(config.antigravityAppPath));

    if (host.valid && port.valid) {
        results.push(await validateUpstreamProtocol(config));
    }

    return results;
}
