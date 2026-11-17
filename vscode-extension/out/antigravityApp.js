"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveAntigravityExecutable = resolveAntigravityExecutable;
exports.matchAntigravityProcess = matchAntigravityProcess;
const child_process_1 = require("child_process");
const fs_1 = require("fs");
const os_1 = require("os");
const path = __importStar(require("path"));
const util_1 = require("util");
function resolveAntigravityExecutable(appPath) {
    const configuredPath = appPath.trim();
    const bundles = configuredPath
        ? [path.resolve(configuredPath)]
        : ['/Applications/Antigravity.app', path.join((0, os_1.homedir)(), 'Applications/Antigravity.app')];
    for (const bundle of bundles) {
        try {
            const executable = (0, child_process_1.execFileSync)('/usr/bin/plutil', [
                '-extract', 'CFBundleExecutable', 'raw', '-expect', 'string', '-n', '--',
                path.join(bundle, 'Contents', 'Info.plist'),
            ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
            if (!executable || executable === '.' || executable === '..' || /[/\r\n]/.test(executable)) {
                continue;
            }
            const resolved = path.join(bundle, 'Contents', 'MacOS', executable);
            if ((0, fs_1.statSync)(resolved).isFile()) {
                (0, fs_1.accessSync)(resolved, fs_1.constants.X_OK);
                return resolved;
            }
        }
        catch {
            // Try the next installation if the bundle is missing or incomplete.
        }
    }
    return undefined;
}
const execProcess = (0, util_1.promisify)(child_process_1.execFile);
/** Match the configured main executable, allowing command-line arguments. */
async function matchAntigravityProcess(executable, cmd) {
    const escaped = executable.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    try {
        await execProcess(`/usr/bin/${cmd}`, ['-f', `^${escaped}([[:space:]]|$)`], { timeout: 5000 });
        return true;
    }
    catch (err) {
        if (err.code === 1) {
            return false;
        }
        throw err;
    }
}
//# sourceMappingURL=antigravityApp.js.map