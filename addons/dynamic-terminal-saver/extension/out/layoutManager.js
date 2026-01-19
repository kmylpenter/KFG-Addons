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
exports.activateLayoutManager = activateLayoutManager;
exports.deactivateLayoutManager = deactivateLayoutManager;
// Layout Manager - Layout States with Dynamic Height
const vscode = __importStar(require("vscode"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const LAYOUT_FILE = 'layout-states.json';
let config = null;
let debounceTimer = null;
let statusBar1;
let statusBar2;
let terminalListener = null;
let outputChannel;
let currentState = 0;
function log(msg) {
    const ts = new Date().toISOString().substring(11, 23);
    outputChannel?.appendLine(`[${ts}] ${msg}`);
}
function getConfigPath() {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders?.length)
        return undefined;
    const dir = path.join(folders[0].uri.fsPath, '.vscode');
    if (!fs.existsSync(dir))
        fs.mkdirSync(dir, { recursive: true });
    return path.join(dir, LAYOUT_FILE);
}
function loadConfig() {
    const p = getConfigPath();
    if (p && fs.existsSync(p)) {
        try {
            return JSON.parse(fs.readFileSync(p, 'utf8'));
        }
        catch { /* ignore */ }
    }
    return { version: '2.0', states: {} };
}
function saveConfig() {
    const p = getConfigPath();
    if (p && config) {
        fs.writeFileSync(p, JSON.stringify(config, null, 2), 'utf8');
        log(`Config saved`);
    }
}
function toProportions(layout) {
    const convert = (groups) => {
        const total = groups.reduce((s, g) => s + (g.size || 1), 0);
        return groups.map(g => ({
            size: Math.round(((g.size || 1) / total) * 1000) / 1000,
            ...(g.groups?.length ? { groups: convert(g.groups) } : {})
        }));
    };
    return { orientation: layout.orientation, groups: convert(layout.groups) };
}
function applyLayout(stateNum) {
    const preset = config?.states[stateNum];
    if (!preset?.layout)
        return;
    if (debounceTimer)
        clearTimeout(debounceTimer);
    debounceTimer = setTimeout(async () => {
        debounceTimer = null;
        log(`Applying State ${stateNum}...`);
        try {
            await vscode.commands.executeCommand('vscode.setEditorLayout', preset.layout);
            currentState = stateNum;
            updateStatusBars();
            log(`State ${stateNum} applied`);
        }
        catch (e) {
            log(`Error: ${e}`);
        }
    }, 150);
}
function findStateForTerminal(name) {
    if (config?.states['1']?.triggers.includes(name))
        return 1;
    if (config?.states['2']?.triggers.includes(name))
        return 2;
    return 0;
}
function updateStatusBars() {
    const s1 = config?.states['1'];
    const s2 = config?.states['2'];
    statusBar1.text = currentState === 1 ? '$(circle-filled) 1' : '$(circle-outline) 1';
    statusBar1.tooltip = s1 ? `Stan 1: ${s1.triggers.join(', ')}\nKliknij aby zapisac` : 'Stan 1: nie ustawiony';
    statusBar1.backgroundColor = currentState === 1 ? new vscode.ThemeColor('statusBarItem.activeBackground') : undefined;
    statusBar2.text = currentState === 2 ? '$(circle-filled) 2' : '$(circle-outline) 2';
    statusBar2.tooltip = s2 ? `Stan 2: ${s2.triggers.join(', ')}\nKliknij aby zapisac` : 'Stan 2: nie ustawiony';
    statusBar2.backgroundColor = currentState === 2 ? new vscode.ThemeColor('statusBarItem.activeBackground') : undefined;
}
async function saveState(stateNum) {
    log(`saveState(${stateNum})`);
    const layout = await vscode.commands.executeCommand('vscode.getEditorLayout');
    if (!layout) {
        vscode.window.showWarningMessage('Nie mozna pobrac layoutu');
        return;
    }
    const proportional = toProportions(layout);
    log(`Layout: ${JSON.stringify(proportional)}`);
    const terminals = vscode.window.terminals.map(t => t.name);
    if (!terminals.length) {
        vscode.window.showWarningMessage('Brak terminali');
        return;
    }
    const otherState = stateNum === 1 ? 2 : 1;
    const otherTriggers = config?.states[otherState]?.triggers || [];
    const items = terminals.map(name => ({
        label: name,
        description: otherTriggers.includes(name) ? `(Stan ${otherState})` : '',
        picked: false
    }));
    const selected = await vscode.window.showQuickPick(items, {
        canPickMany: true,
        placeHolder: 'Ktore terminale WLACZAJA ten layout?',
        title: `Stan ${stateNum} - wybierz triggery`
    });
    if (!selected?.length) {
        vscode.window.showInformationMessage('Anulowano');
        return;
    }
    const triggers = selected.map(s => s.label);
    // Remove from other state
    if (config?.states[otherState]) {
        config.states[otherState].triggers = config.states[otherState].triggers.filter(t => !triggers.includes(t));
    }
    if (!config)
        config = { version: '2.0', states: {} };
    config.states[stateNum] = { layout: proportional, triggers };
    currentState = stateNum;
    saveConfig();
    updateStatusBars();
    vscode.window.showInformationMessage(`Stan ${stateNum} zapisany. Triggery: ${triggers.join(', ')}`);
}
function activateLayoutManager(context) {
    outputChannel = vscode.window.createOutputChannel('Layout Manager');
    context.subscriptions.push(outputChannel);
    log('=== Layout States ACTIVATED ===');
    if (debounceTimer) {
        clearTimeout(debounceTimer);
        debounceTimer = null;
    }
    if (terminalListener) {
        terminalListener.dispose();
        terminalListener = null;
    }
    config = loadConfig();
    log(`Loaded: ${JSON.stringify(config)}`);
    // Status bars
    statusBar1 = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 102);
    statusBar1.command = 'dynamicTerminalSaver.saveState1';
    statusBar1.show();
    context.subscriptions.push(statusBar1);
    statusBar2 = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 101);
    statusBar2.command = 'dynamicTerminalSaver.saveState2';
    statusBar2.show();
    context.subscriptions.push(statusBar2);
    updateStatusBars();
    // Commands
    context.subscriptions.push(vscode.commands.registerCommand('dynamicTerminalSaver.saveState1', () => saveState(1)), vscode.commands.registerCommand('dynamicTerminalSaver.saveState2', () => saveState(2)), vscode.commands.registerCommand('dynamicTerminalSaver.toggleLayoutLock', () => saveState(1)));
    // Terminal listener - auto-switch layout on terminal change
    terminalListener = vscode.window.onDidChangeActiveTerminal((terminal) => {
        if (!terminal)
            return;
        log(`Terminal: ${terminal.name}`);
        const state = findStateForTerminal(terminal.name);
        if (state && state !== currentState) {
            log(`Switching to State ${state}`);
            applyLayout(state);
        }
    });
    context.subscriptions.push(terminalListener);
    log('=== Layout States READY ===');
}
function deactivateLayoutManager() {
    if (debounceTimer) {
        clearTimeout(debounceTimer);
        debounceTimer = null;
    }
    if (terminalListener) {
        terminalListener.dispose();
        terminalListener = null;
    }
}
//# sourceMappingURL=layoutManager.js.map