import { execFile, execFileSync } from 'child_process';
import { accessSync, constants, statSync } from 'fs';
import { homedir } from 'os';
import * as path from 'path';
import { promisify } from 'util';

export function resolveAntigravityExecutable(appPath: string): string | undefined {
    const configuredPath = appPath.trim();
    const bundles = configuredPath
        ? [path.resolve(configuredPath)]
        : ['/Applications/Antigravity.app', path.join(homedir(), 'Applications/Antigravity.app')];

    for (const bundle of bundles) {
        try {
            const executable = execFileSync('/usr/bin/plutil', [
                '-extract', 'CFBundleExecutable', 'raw', '-expect', 'string', '-n', '--',
                path.join(bundle, 'Contents', 'Info.plist'),
            ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
            if (!executable || executable === '.' || executable === '..' || /[/\r\n]/.test(executable)) {
                continue;
            }
            const resolved = path.join(bundle, 'Contents', 'MacOS', executable);
            if (statSync(resolved).isFile()) {
                accessSync(resolved, constants.X_OK);
                return resolved;
            }
        } catch {
            // Try the next installation if the bundle is missing or incomplete.
        }
    }
    return undefined;
}

const execProcess = promisify(execFile);

/** Match the configured main executable, allowing command-line arguments. */
export async function matchAntigravityProcess(executable: string, cmd: 'pgrep' | 'pkill'): Promise<boolean> {
    const escaped = executable.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    try {
        await execProcess(`/usr/bin/${cmd}`, ['-f', `^${escaped}([[:space:]]|$)`], { timeout: 5000 });
        return true;
    } catch (err) {
        if ((err as { code?: number }).code === 1) {
            return false;
        }
        throw err;
    }
}
