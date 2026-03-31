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
exports.activate = activate;
exports.deactivate = deactivate;
// Only load vscode and path eagerly - they're lightweight
const vscode = __importStar(require("vscode"));
const path = __importStar(require("path"));
// Lazy-loaded modules (heavy timeline/backup/clipboard logic)
let copyAndUnselect_1;
let copyAndCreateTimeline_1;
let pasteImage_1;
let clipboardMonitor_1;
let changeTracker_1;
let timelineManager_1;
let timelineManifest_1;
let autoBackupManager_1;
let child_process_1;
let _heavyModulesLoaded = false;
function loadHeavyModules() {
    if (_heavyModulesLoaded) return;
    _heavyModulesLoaded = true;
    copyAndUnselect_1 = require("./commands/copyAndUnselect");
    copyAndCreateTimeline_1 = require("./commands/copyAndCreateTimeline");
    pasteImage_1 = require("./commands/pasteImage");
    clipboardMonitor_1 = require("./utils/clipboardMonitor");
    changeTracker_1 = require("./utils/changeTracker");
    timelineManager_1 = require("./utils/timelineManager");
    timelineManifest_1 = require("./utils/timelineManifest");
    autoBackupManager_1 = require("./utils/autoBackupManager");
    child_process_1 = require("child_process");
}
let changeTracker;
let awaitingCtrlC = false;
let timeoutHandle = null;
let outputChannel;
let clipboardMonitor = null;
let _managersInitialized = false;
function ensureManagers(context) {
    if (_managersInitialized) return;
    _managersInitialized = true;
    loadHeavyModules();
    outputChannel = outputChannel || vscode.window.createOutputChannel('Clipboard Helper');
    changeTracker = new changeTracker_1.ChangeTracker();
    timelineManager_1.TimelineManager.initialize(context, outputChannel);
    timelineManifest_1.TimelineManifest.initialize(context.extensionPath, outputChannel);
    autoBackupManager_1.AutoBackupManager.initialize(outputChannel);
    // Start clipboard monitor
    clipboardMonitor = new clipboardMonitor_1.ClipboardMonitor(outputChannel, context.extensionPath);
    clipboardMonitor.start();
    // Track document changes
    let disposable4 = vscode.workspace.onDidChangeTextDocument((event) => {
        const document = event.document;
        if (vscode.window.visibleTextEditors.some((editor) => editor.document === document)) {
            for (const change of event.contentChanges) {
                changeTracker.trackChange(document, change);
            }
        }
    });
    context.subscriptions.push(disposable4);
    // Auto-backup on every save (debounced 30s)
    let disposable5 = vscode.workspace.onDidSaveTextDocument(async (document) => {
        if (document.uri.scheme !== 'file') return;
        await autoBackupManager_1.AutoBackupManager.handleSave(document);
    });
    context.subscriptions.push(disposable5);
    // FileSystemWatcher
    const fileWatcher = vscode.workspace.createFileSystemWatcher('**/*');
    const pendingBackups = new Map();
    const COOLDOWN_MS = 2000;
    fileWatcher.onDidChange(async (uri) => {
        if (uri.scheme !== 'file') return;
        const fsPath = uri.fsPath;
        if (fsPath.includes('node_modules') || fsPath.includes('.git') ||
            fsPath.includes('\\out\\') || fsPath.includes('/out/') ||
            fsPath.includes('.claude\\debug') || fsPath.includes('.claude/debug') ||
            fsPath.includes('.timeline-manifest')) return;
        const uriString = uri.toString();
        if (pendingBackups.has(uriString)) {
            clearTimeout(pendingBackups.get(uriString));
            outputChannel.appendLine(`[FileWatcher] Cooldown reset for: ${path.basename(fsPath)}`);
        }
        const timeoutId = setTimeout(async () => {
            pendingBackups.delete(uriString);
            outputChannel.appendLine(`[FileWatcher] Processing after cooldown: ${path.basename(fsPath)}`);
            try {
                const document = await vscode.workspace.openTextDocument(uri);
                await autoBackupManager_1.AutoBackupManager.handleSave(document);
            } catch (error) {
                outputChannel.appendLine(`[FileWatcher] Error: ${error}`);
            }
        }, COOLDOWN_MS);
        pendingBackups.set(uriString, timeoutId);
    });
    fileWatcher.onDidCreate(async (uri) => {
        if (uri.scheme !== 'file') return;
        const fsPath = uri.fsPath;
        if (fsPath.includes('node_modules') || fsPath.includes('.git') ||
            fsPath.includes('\\out\\') || fsPath.includes('/out/') ||
            fsPath.includes('.claude\\debug') || fsPath.includes('.claude/debug') ||
            fsPath.includes('.timeline-manifest')) return;
        const uriString = uri.toString();
        outputChannel.appendLine(`[FileWatcher] NEW FILE created: ${path.basename(fsPath)}`);
        if (pendingBackups.has(uriString)) {
            clearTimeout(pendingBackups.get(uriString));
        }
        const timeoutId = setTimeout(async () => {
            pendingBackups.delete(uriString);
            outputChannel.appendLine(`[FileWatcher] Processing NEW file after cooldown: ${path.basename(fsPath)}`);
            try {
                const document = await vscode.workspace.openTextDocument(uri);
                await autoBackupManager_1.AutoBackupManager.handleSave(document);
            } catch (error) {
                outputChannel.appendLine(`[FileWatcher] Error creating backup for new file: ${error}`);
            }
        }, COOLDOWN_MS);
        pendingBackups.set(uriString, timeoutId);
    });
    context.subscriptions.push(fileWatcher);
}
function activate(context) {
    // FAST PATH: Register commands IMMEDIATELY (no heavy imports needed)
    // This prevents "Activating Extension" delay on Ctrl+A/Ctrl+C
    outputChannel = vscode.window.createOutputChannel('Clipboard Helper');
    // Ctrl+A - selectAll (lightweight, no heavy deps needed)
    context.subscriptions.push(
        vscode.commands.registerCommand('clipboardHelper.selectAllWithTimeout', async () => {
            if (timeoutHandle) clearTimeout(timeoutHandle);
            // Execute select all IMMEDIATELY
            await vscode.commands.executeCommand('editor.action.selectAll');
            const config = vscode.workspace.getConfiguration('clipboardHelper');
            const timeoutMs = config.get('ctrlACtrlCTimeout', 2000);
            if (timeoutMs === 0) return;
            awaitingCtrlC = true;
            await vscode.commands.executeCommand('setContext', 'clipboardHelper.awaitingCtrlC', true);
            timeoutHandle = setTimeout(() => {
                awaitingCtrlC = false;
                vscode.commands.executeCommand('setContext', 'clipboardHelper.awaitingCtrlC', false);
                timeoutHandle = null;
            }, timeoutMs);
        })
    );
    // Ctrl+C with selection - copy and unselect (lightweight)
    context.subscriptions.push(
        vscode.commands.registerCommand('clipboardHelper.copyAndUnselect', async () => {
            loadHeavyModules();
            await (0, copyAndUnselect_1.copyAndUnselect)();
        })
    );
    // Ctrl+C after Ctrl+A - copy + timeline (needs heavy modules)
    context.subscriptions.push(
        vscode.commands.registerCommand('clipboardHelper.copyAndCreateTimeline', async () => {
            if (timeoutHandle) {
                clearTimeout(timeoutHandle);
                timeoutHandle = null;
            }
            const wasAwaitingCtrlC = awaitingCtrlC;
            awaitingCtrlC = false;
            await vscode.commands.executeCommand('setContext', 'clipboardHelper.awaitingCtrlC', false);
            ensureManagers(context);
            if (wasAwaitingCtrlC) {
                await (0, copyAndCreateTimeline_1.copyAndCreateTimeline)(changeTracker);
            } else {
                await (0, copyAndUnselect_1.copyAndUnselect)();
            }
        })
    );
    // Ctrl+Shift+V in terminal - paste image
    context.subscriptions.push(
        vscode.commands.registerCommand('clipboardHelper.pasteImage', async () => {
            ensureManagers(context);
            if (clipboardMonitor && clipboardMonitor.hasPending()) {
                const pendingPath = clipboardMonitor.getPendingPath();
                if (pendingPath) {
                    outputChannel.appendLine(`[PasteImage] Using pending screenshot: ${pendingPath}`);
                    const config = vscode.workspace.getConfiguration('clipboardHelper');
                    const prefix = config.get('pasteImagePrefix') || 'Sprawdz ';
                    let terminal = vscode.window.activeTerminal;
                    if (!terminal) {
                        terminal = vscode.window.createTerminal('Claude');
                        terminal.show();
                    }
                    const textToSend = `${prefix}${pendingPath.replace(/\\/g, '/')}`;
                    await vscode.env.clipboard.writeText(textToSend);
                    await vscode.commands.executeCommand('workbench.action.terminal.paste');
                    vscode.window.showInformationMessage(`Screenshot: ${require('path').basename(pendingPath)}`);
                    return;
                }
            }
            await (0, pasteImage_1.pasteImage)(outputChannel, context.extensionPath);
        })
    );
    // Toggle clipboard monitor
    context.subscriptions.push(
        vscode.commands.registerCommand('clipboardHelper.toggleClipboardMonitor', () => {
            ensureManagers(context);
            if (clipboardMonitor) {
                if (clipboardMonitor.getIsRunning()) {
                    clipboardMonitor.stop();
                    vscode.window.showInformationMessage('Clipboard monitor zatrzymany.');
                } else {
                    clipboardMonitor.start();
                }
            }
        })
    );
    // DEFERRED: Initialize heavy managers after commands are registered
    // This runs after a short delay so Ctrl+A works instantly
    setTimeout(() => ensureManagers(context), 500);
}
function deactivate() {
    if (timeoutHandle) clearTimeout(timeoutHandle);
    if (clipboardMonitor) clipboardMonitor.stop();
    if (changeTracker) changeTracker.clear();
    if (_heavyModulesLoaded && timelineManifest_1 && timelineManifest_1.TimelineManifest.hasUpdates()) {
        try {
            const mergeScriptPath = path.join(__dirname, 'utils', 'timelineMerge.js');
            const manifestPath = timelineManifest_1.TimelineManifest.getManifestPath();
            const extensionPath = path.join(__dirname, '..');
            if (!child_process_1) child_process_1 = require("child_process");
            const child = (0, child_process_1.spawn)('node', [mergeScriptPath, manifestPath, extensionPath], {
                detached: true,
                stdio: 'ignore'
            });
            child.unref();
            outputChannel.appendLine('[Deactivate] Spawned timeline merge in background');
        } catch (error) {
            outputChannel.appendLine(`[Deactivate] Failed to spawn merge: ${error}`);
        }
    }
}
//# sourceMappingURL=extension.js.map
