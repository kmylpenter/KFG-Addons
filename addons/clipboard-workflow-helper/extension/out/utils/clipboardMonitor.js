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
exports.ClipboardMonitor = void 0;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
const child_process_1 = require("child_process");
const os = __importStar(require("os"));
const readline = __importStar(require("readline"));
class ClipboardMonitor {
    constructor(outputChannel, extensionPath) {
        this.process = null;
        this.pendingScreenshotPath = null;
        this.isRunning = false;
        this.outputChannel = outputChannel;
        this.extensionPath = extensionPath;
    }
    start() {
        const config = vscode.workspace.getConfiguration('clipboardHelper');
        const enabled = config.get('autoDetectScreenshot') ?? false;
        if (!enabled) {
            this.outputChannel.appendLine('[ClipboardMonitor] Auto-detect disabled in settings');
            return;
        }
        if (this.isRunning) {
            this.outputChannel.appendLine('[ClipboardMonitor] Already running');
            return;
        }
        // Get screenshot folder
        let screenshotFolder = config.get('screenshotFolder') || '';
        if (!screenshotFolder) {
            screenshotFolder = path.join(os.tmpdir(), 'claude-screenshots');
        }
        // Ensure folder exists
        if (!fs.existsSync(screenshotFolder)) {
            fs.mkdirSync(screenshotFolder, { recursive: true });
        }
        const exePath = path.join(this.extensionPath, 'ClipboardListener.exe');
        if (!fs.existsSync(exePath)) {
            this.outputChannel.appendLine('[ClipboardMonitor] ClipboardListener.exe not found!');
            return;
        }
        this.outputChannel.appendLine(`[ClipboardMonitor] Starting listener...`);
        this.outputChannel.appendLine(`[ClipboardMonitor] Folder: ${screenshotFolder}`);
        try {
            this.process = (0, child_process_1.spawn)(exePath, [screenshotFolder], {
                windowsHide: true,
                stdio: ['ignore', 'pipe', 'pipe']
            });
            this.isRunning = true;
            // Read stdout line by line
            if (this.process.stdout) {
                const rl = readline.createInterface({ input: this.process.stdout });
                rl.on('line', (line) => {
                    this.outputChannel.appendLine(`[ClipboardMonitor] ${line}`);
                    if (line === 'READY') {
                        this.outputChannel.appendLine('[ClipboardMonitor] Listener ready - monitoring clipboard');
                        vscode.window.showInformationMessage('Clipboard monitor aktywny. Zrób screenshot (Win+Shift+S).');
                    }
                    else if (line.startsWith('NEW:')) {
                        const filepath = line.substring(4);
                        this.pendingScreenshotPath = filepath;
                        this.outputChannel.appendLine(`[ClipboardMonitor] Screenshot ready: ${path.basename(filepath)}`);
                        // Show notification with action
                        vscode.window.showInformationMessage(`Screenshot gotowy! Ctrl+Shift+V w terminalu.`, 'Wklej teraz').then(selection => {
                            if (selection === 'Wklej teraz') {
                                vscode.commands.executeCommand('clipboardHelper.pasteImage');
                            }
                        });
                    }
                    else if (line.startsWith('ERROR:')) {
                        this.outputChannel.appendLine(`[ClipboardMonitor] Error: ${line.substring(6)}`);
                    }
                });
            }
            // Handle stderr
            if (this.process.stderr) {
                this.process.stderr.on('data', (data) => {
                    this.outputChannel.appendLine(`[ClipboardMonitor] stderr: ${data}`);
                });
            }
            // Handle process exit
            this.process.on('exit', (code) => {
                this.outputChannel.appendLine(`[ClipboardMonitor] Process exited with code ${code}`);
                this.isRunning = false;
                this.process = null;
            });
            this.process.on('error', (err) => {
                this.outputChannel.appendLine(`[ClipboardMonitor] Process error: ${err.message}`);
                this.isRunning = false;
                this.process = null;
            });
        }
        catch (error) {
            this.outputChannel.appendLine(`[ClipboardMonitor] Failed to start: ${error}`);
            this.isRunning = false;
        }
    }
    stop() {
        if (this.process) {
            this.outputChannel.appendLine('[ClipboardMonitor] Stopping...');
            this.process.kill();
            this.process = null;
            this.isRunning = false;
        }
    }
    // Get pending screenshot path (if any) and clear it
    getPendingPath() {
        const p = this.pendingScreenshotPath;
        this.pendingScreenshotPath = null;
        return p;
    }
    hasPending() {
        return this.pendingScreenshotPath !== null;
    }
    getIsRunning() {
        return this.isRunning;
    }
}
exports.ClipboardMonitor = ClipboardMonitor;
//# sourceMappingURL=clipboardMonitor.js.map