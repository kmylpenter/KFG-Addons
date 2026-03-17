// Layout Manager - Layout States with Dynamic Height
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

const LAYOUT_FILE = 'layout-states.json';

interface LayoutGroup {
  size?: number;
  groups?: LayoutGroup[];
}

interface EditorLayout {
  orientation: number;
  groups: LayoutGroup[];
}

interface LayoutState {
  layout: EditorLayout;
  triggers: string[];
}

interface LayoutConfig {
  version: string;
  states: Record<string, LayoutState>;
}

let config: LayoutConfig | null = null;
let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let statusBar1: vscode.StatusBarItem;
let statusBar2: vscode.StatusBarItem;
let terminalListener: vscode.Disposable | null = null;
let outputChannel: vscode.OutputChannel;
let currentState = 0;

function log(msg: string): void {
  const ts = new Date().toISOString().substring(11, 23);
  outputChannel?.appendLine(`[${ts}] ${msg}`);
}

function getConfigPath(): string | undefined {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders?.length) return undefined;
  const dir = path.join(folders[0].uri.fsPath, '.vscode');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, LAYOUT_FILE);
}

function loadConfig(): LayoutConfig {
  const p = getConfigPath();
  if (p && fs.existsSync(p)) {
    try {
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    } catch { /* ignore */ }
  }
  return { version: '2.0', states: {} };
}

function saveConfig(): void {
  const p = getConfigPath();
  if (p && config) {
    fs.writeFileSync(p, JSON.stringify(config, null, 2), 'utf8');
    log(`Config saved`);
  }
}

function toProportions(layout: EditorLayout): EditorLayout {
  const convert = (groups: LayoutGroup[]): LayoutGroup[] => {
    const total = groups.reduce((s, g) => s + (g.size || 1), 0);
    return groups.map(g => ({
      size: Math.round(((g.size || 1) / total) * 1000) / 1000,
      ...(g.groups?.length ? { groups: convert(g.groups) } : {})
    }));
  };
  return { orientation: layout.orientation, groups: convert(layout.groups) };
}

function applyLayout(stateNum: number): void {
  const preset = config?.states[stateNum];
  if (!preset?.layout) return;

  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(async () => {
    debounceTimer = null;
    log(`Applying State ${stateNum}...`);
    try {
      await vscode.commands.executeCommand('vscode.setEditorLayout', preset.layout);
      currentState = stateNum;
      updateStatusBars();
      log(`State ${stateNum} applied`);
    } catch (e) {
      log(`Error: ${e}`);
    }
  }, 150);
}

function findStateForTerminal(name: string): number {
  if (config?.states['1']?.triggers.includes(name)) return 1;
  if (config?.states['2']?.triggers.includes(name)) return 2;
  return 0;
}

function updateStatusBars(): void {
  const s1 = config?.states['1'];
  const s2 = config?.states['2'];

  statusBar1.text = currentState === 1 ? '$(circle-filled) 1' : '$(circle-outline) 1';
  statusBar1.tooltip = s1 ? `Stan 1: ${s1.triggers.join(', ')}\nKliknij aby zapisac` : 'Stan 1: nie ustawiony';
  statusBar1.backgroundColor = currentState === 1 ? new vscode.ThemeColor('statusBarItem.activeBackground') : undefined;

  statusBar2.text = currentState === 2 ? '$(circle-filled) 2' : '$(circle-outline) 2';
  statusBar2.tooltip = s2 ? `Stan 2: ${s2.triggers.join(', ')}\nKliknij aby zapisac` : 'Stan 2: nie ustawiony';
  statusBar2.backgroundColor = currentState === 2 ? new vscode.ThemeColor('statusBarItem.activeBackground') : undefined;
}

async function saveState(stateNum: number): Promise<void> {
  log(`saveState(${stateNum})`);

  const layout = await vscode.commands.executeCommand<EditorLayout>('vscode.getEditorLayout');
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

  if (!config) config = { version: '2.0', states: {} };
  config.states[stateNum] = { layout: proportional, triggers };
  currentState = stateNum;

  saveConfig();
  updateStatusBars();
  vscode.window.showInformationMessage(`Stan ${stateNum} zapisany. Triggery: ${triggers.join(', ')}`);
}

export function activateLayoutManager(context: vscode.ExtensionContext): void {
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
  context.subscriptions.push(
    vscode.commands.registerCommand('dynamicTerminalSaver.saveState1', () => saveState(1)),
    vscode.commands.registerCommand('dynamicTerminalSaver.saveState2', () => saveState(2)),
    vscode.commands.registerCommand('dynamicTerminalSaver.toggleLayoutLock', () => saveState(1))
  );

  // Terminal listener - auto-switch layout on terminal change
  terminalListener = vscode.window.onDidChangeActiveTerminal((terminal) => {
    if (!terminal) return;
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

export function deactivateLayoutManager(): void {
  if (debounceTimer) {
    clearTimeout(debounceTimer);
    debounceTimer = null;
  }
  if (terminalListener) {
    terminalListener.dispose();
    terminalListener = null;
  }
}
