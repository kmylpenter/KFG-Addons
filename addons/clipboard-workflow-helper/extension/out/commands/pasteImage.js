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
exports.pasteImage = pasteImage;
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
const child_process_1 = require("child_process");
const util_1 = require("util");
const os = __importStar(require("os"));
const execFileAsync = (0, util_1.promisify)(child_process_1.execFile);
// Cleanup old screenshots (runs in background after paste)
function cleanupOldScreenshots(folder, retentionDays, outputChannel) {
    if (retentionDays <= 0)
        return; // Disabled
    const cutoffTime = Date.now() - (retentionDays * 24 * 60 * 60 * 1000);
    fs.readdir(folder, (err, files) => {
        if (err)
            return;
        let deletedCount = 0;
        files.forEach(file => {
            if (!file.startsWith('screenshot_') || !file.endsWith('.png'))
                return;
            const filepath = path.join(folder, file);
            fs.stat(filepath, (err, stats) => {
                if (err)
                    return;
                if (stats.mtimeMs < cutoffTime) {
                    fs.unlink(filepath, (err) => {
                        if (!err) {
                            deletedCount++;
                            outputChannel.appendLine(`[Cleanup] Deleted old screenshot: ${file}`);
                        }
                    });
                }
            });
        });
    });
}
/**
 * Paste image from clipboard to file and insert path into terminal
 */
async function pasteImage(outputChannel, extensionPath) {
    const config = vscode.workspace.getConfiguration('clipboardHelper');
    const prefix = config.get('pasteImagePrefix') || 'Sprawdz ';
    // Get screenshot folder - default to TEMP (avoids path issues with special chars)
    let screenshotFolder = config.get('screenshotFolder') || '';
    if (!screenshotFolder) {
        // Use TEMP by default - workspace paths often have special chars that break GDI+
        screenshotFolder = path.join(os.tmpdir(), 'claude-screenshots');
    }
    // Ensure folder exists
    if (!fs.existsSync(screenshotFolder)) {
        fs.mkdirSync(screenshotFolder, { recursive: true });
    }
    // Generate filename
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const filename = `screenshot_${timestamp}.png`;
    const filepath = path.join(screenshotFolder, filename);
    outputChannel.appendLine(`[PasteImage] Attempting to save clipboard to: ${filepath}`);
    // Use compiled C# exe for speed (much faster than PowerShell)
    const exePath = path.join(extensionPath, 'ClipboardToFile.exe');
    try {
        const { stdout, stderr } = await execFileAsync(exePath, [filepath], { windowsHide: true });
        const result = stdout.trim();
        outputChannel.appendLine(`[PasteImage] ClipboardToFile result: ${result}`);
        if (stderr) {
            outputChannel.appendLine(`[PasteImage] stderr: ${stderr}`);
        }
        if (result === 'NO_IMAGE') {
            vscode.window.showWarningMessage('Brak obrazu w schowku. Użyj Win+Shift+S aby zrobić screenshot.');
            return;
        }
        if (result.startsWith('ERROR:')) {
            throw new Error(`Save failed: ${result}`);
        }
        if (result !== 'OK') {
            outputChannel.appendLine(`[PasteImage] Unexpected result: ${result}`);
            throw new Error(`ClipboardToFile returned: ${result}`);
        }
        // Verify file was created
        if (!fs.existsSync(filepath)) {
            throw new Error('Screenshot file was not created');
        }
        outputChannel.appendLine(`[PasteImage] Screenshot saved: ${filepath}`);
        // Get active terminal or create one
        let terminal = vscode.window.activeTerminal;
        if (!terminal) {
            terminal = vscode.window.createTerminal('Claude');
            terminal.show();
        }
        // Use clipboard + paste instead of sendText (sendText breaks with Ink-based terminals like Claude Code)
        const textToSend = `${prefix}${filepath.replace(/\\/g, '/')}`;
        await vscode.env.clipboard.writeText(textToSend);
        await vscode.commands.executeCommand('workbench.action.terminal.paste');
        vscode.window.showInformationMessage(`Screenshot: ${filename}`);
        // Cleanup old screenshots in background (after paste completes)
        const retentionDays = config.get('screenshotRetentionDays') ?? 7;
        setTimeout(() => cleanupOldScreenshots(screenshotFolder, retentionDays, outputChannel), 100);
    }
    catch (error) {
        outputChannel.appendLine(`[PasteImage] Error: ${error}`);
        vscode.window.showErrorMessage(`Claude Paste: ${error}`);
    }
}
//# sourceMappingURL=pasteImage.js.map