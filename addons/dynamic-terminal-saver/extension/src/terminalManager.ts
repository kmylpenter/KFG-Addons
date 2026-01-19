// Logika zapisywania i przywracania terminali
import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { SavedTerminal, TerminalState } from './types';

// Autodetekcja PC - nazwa pliku per komputer
function getComputerId(): string {
  // Priorytet: COMPUTERNAME > USERNAME > hostname
  return process.env.COMPUTERNAME || process.env.USERNAME || os.hostname() || 'default';
}

const STATE_FILE = `terminals-state-${getComputerId()}.json`;
const STATE_VERSION = '1.0';

// Pula kolorow dla terminali (oryginalne - dzialajace)
const TERMINAL_COLORS = [
  'terminal.ansiRed',
  'terminal.ansiGreen',
  'terminal.ansiBlue',
  'terminal.ansiYellow',
  'terminal.ansiMagenta',
  'terminal.ansiCyan'
];

// Pula ikonek dla terminali (VS Code ThemeIcon)
const TERMINAL_ICONS = [
  'rocket',
  'folder',
  'code',
  'gear',
  'debug',
  'beaker',
  'package',
  'database',
  'server',
  'cloud',
  'globe',
  'home',
  'briefcase',
  'book',
  'lightbulb',
  'tools',
  'wrench',
  'plug',
  'zap',
  'flame',
  'heart',
  'star',
  'bookmark',
  'tag'
];

// Hash nazwy terminala do wyboru koloru (deterministyczny)
function getColorForName(name: string, usedColors: Set<string> = new Set()): string {
  // Prosty hash nazwy
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = ((hash << 5) - hash) + name.charCodeAt(i);
    hash = hash & hash; // Convert to 32bit integer
  }
  hash = Math.abs(hash);

  // Znajdz wolny kolor zaczynajac od hash
  const startIdx = hash % TERMINAL_COLORS.length;
  for (let i = 0; i < TERMINAL_COLORS.length; i++) {
    const idx = (startIdx + i) % TERMINAL_COLORS.length;
    const color = TERMINAL_COLORS[idx];
    if (!usedColors.has(color)) {
      return color;
    }
  }

  // Fallback - wszystkie zajete, uzyj hash
  return TERMINAL_COLORS[startIdx];
}

// Hash nazwy terminala do wyboru ikonki (deterministyczny)
function getIconForName(name: string, usedIcons: Set<string> = new Set()): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = ((hash << 5) - hash) + name.charCodeAt(i);
    hash = hash & hash;
  }
  hash = Math.abs(hash);

  const startIdx = hash % TERMINAL_ICONS.length;
  for (let i = 0; i < TERMINAL_ICONS.length; i++) {
    const idx = (startIdx + i) % TERMINAL_ICONS.length;
    const icon = TERMINAL_ICONS[idx];
    if (!usedIcons.has(icon)) {
      return icon;
    }
  }
  return TERMINAL_ICONS[startIdx];
}

// Pobierz sciezke do pliku stanu - w glownym folderze workspace (obok .code-workspace)
function getStateFilePath(): string | undefined {
  // Opcja 1: Uzyj workspace file location (najlepsze)
  const workspaceFile = vscode.workspace.workspaceFile;
  if (workspaceFile && workspaceFile.scheme === 'file') {
    const workspaceDir = path.dirname(workspaceFile.fsPath);
    const vscodeFolder = path.join(workspaceDir, '.vscode');
    if (!fs.existsSync(vscodeFolder)) {
      fs.mkdirSync(vscodeFolder, { recursive: true });
    }
    return path.join(vscodeFolder, STATE_FILE);
  }

  // Opcja 2: Fallback - workspace folders
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders || workspaceFolders.length === 0) {
    return undefined;
  }

  // Szukaj folderu ktory BEZPOSREDNIO zawiera .vscode/extensions/
  for (const folder of workspaceFolders) {
    const extensionsFolder = path.join(folder.uri.fsPath, '.vscode', 'extensions');
    if (fs.existsSync(extensionsFolder)) {
      const vscodeFolder = path.join(folder.uri.fsPath, '.vscode');
      return path.join(vscodeFolder, STATE_FILE);
    }
  }

  // Fallback: pierwszy workspace folder
  const firstFolder = workspaceFolders[0].uri.fsPath;
  const vscodeFolder = path.join(firstFolder, '.vscode');
  if (!fs.existsSync(vscodeFolder)) {
    fs.mkdirSync(vscodeFolder, { recursive: true });
  }
  return path.join(vscodeFolder, STATE_FILE);
}

// Znajdz workspace folder po nazwie
function findWorkspaceFolderByName(name: string): vscode.WorkspaceFolder | undefined {
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders) {return undefined;}

  // Dokladne dopasowanie
  let folder = workspaceFolders.find(f => f.name === name);
  if (folder) {return folder;}

  // Dopasowanie case-insensitive
  folder = workspaceFolders.find(f => f.name.toLowerCase() === name.toLowerCase());
  if (folder) {return folder;}

  // Czesciowe dopasowanie (nazwa zawiera sie w folderze lub odwrotnie)
  folder = workspaceFolders.find(f =>
    f.name.toLowerCase().includes(name.toLowerCase()) ||
    name.toLowerCase().includes(f.name.toLowerCase())
  );

  return folder;
}

// Zapisz stan terminali
export async function saveTerminalState(): Promise<void> {
  const stateFilePath = getStateFilePath();
  if (!stateFilePath) {
    vscode.window.showWarningMessage('Brak otwartego workspace - nie mozna zapisac stanu terminali');
    return;
  }

  const terminals = vscode.window.terminals;
  if (terminals.length === 0) {
    vscode.window.showWarningMessage('Brak otwartych terminali do zapisania');
    return;
  }

  const savedTerminals: SavedTerminal[] = [];
  const seenNames = new Set<string>(); // Do filtrowania duplikatow nazw
  const usedColors = new Set<string>(); // Do unikania duplikatow kolorow
  const usedIcons = new Set<string>();  // Do unikania duplikatow ikonek

  for (let i = 0; i < terminals.length; i++) {
    const terminal = terminals[i];
    const name = terminal.name;

    // Filtruj duplikaty nazw (case-insensitive)
    const nameNormalized = name.toLowerCase();
    if (seenNames.has(nameNormalized)) {
      continue; // Pomin duplikat nazwy
    }

    // Probuj znalezc cwd z roznych zrodel
    let cwd = '';

    // Opcja 1: Shell Integration API (VS Code 1.93+) - najdokladniejsze
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const shellIntegration = (terminal as any).shellIntegration;
    if (shellIntegration?.cwd) {
      cwd = shellIntegration.cwd.fsPath || shellIntegration.cwd.toString();
    }

    // Opcja 2: creationOptions.cwd (jesli terminal byl utworzony z tym parametrem)
    if (!cwd) {
      const creationOptions = terminal.creationOptions as vscode.TerminalOptions | undefined;
      if (creationOptions?.cwd) {
        if (typeof creationOptions.cwd === 'string') {
          cwd = creationOptions.cwd;
        } else {
          cwd = creationOptions.cwd.fsPath;
        }
      }
    }

    // Opcja 3: heurystyka - nazwa terminala = nazwa workspace folder
    if (!cwd) {
      const folder = findWorkspaceFolderByName(name);
      if (folder) {
        cwd = folder.uri.fsPath;
      }
    }

    // Opcja 4: fallback na pierwszy workspace folder
    if (!cwd && vscode.workspace.workspaceFolders) {
      cwd = vscode.workspace.workspaceFolders[0].uri.fsPath;
    }

    // Zapisz jako unikalne (tylko nazwy musza byc unikalne, CWD moze sie powtarzac)
    seenNames.add(nameNormalized);

    // Przydziel unikalny kolor i ikonke na podstawie nazwy
    const color = getColorForName(name, usedColors);
    usedColors.add(color);
    const icon = getIconForName(name, usedIcons);
    usedIcons.add(icon);

    savedTerminals.push({
      name,
      cwd,
      splitIndex: savedTerminals.length,
      color,
      icon
    });
  }

  const state: TerminalState = {
    version: STATE_VERSION,
    savedAt: new Date().toISOString(),
    terminals: savedTerminals
  };

  try {
    fs.writeFileSync(stateFilePath, JSON.stringify(state, null, 2), 'utf8');
    vscode.window.showInformationMessage(`Zapisano ${savedTerminals.length} terminali`);
  } catch (error) {
    vscode.window.showErrorMessage(`Blad zapisu stanu terminali: ${error}`);
  }
}

// Pobierz zapisane terminale z pliku
function getSavedTerminals(): SavedTerminal[] | undefined {
  const stateFilePath = getStateFilePath();
  if (!stateFilePath || !fs.existsSync(stateFilePath)) {
    return undefined;
  }
  try {
    const content = fs.readFileSync(stateFilePath, 'utf8');
    const state: TerminalState = JSON.parse(content);
    return state.terminals;
  } catch {
    return undefined;
  }
}

// Otworz wszystkie terminale normalnie (jako tabs)
async function openAllTerminalsNormally(terminals: SavedTerminal[]): Promise<void> {
  let firstTerminal: vscode.Terminal | null = null;
  const usedIcons = new Set<string>();

  for (const saved of terminals) {
    const color = saved.color || TERMINAL_COLORS[0];
    // Uzyj zapisanej ikonki lub wygeneruj nowa
    const icon = saved.icon || getIconForName(saved.name, usedIcons);
    usedIcons.add(icon);

    const terminal = vscode.window.createTerminal({
      name: saved.name,
      cwd: saved.cwd || undefined,
      color: new vscode.ThemeColor(color),
      iconPath: new vscode.ThemeIcon(icon)
    });

    if (!firstTerminal) {
      firstTerminal = terminal;
    }

    await new Promise(resolve => setTimeout(resolve, 200));
  }

  // Pokaz panel terminala (pierwszy terminal)
  if (firstTerminal) {
    firstTerminal.show(false); // false = nie zabieraj focus z editora
  }
}


// Przywroc stan terminali (z wyborem)
export async function restoreTerminalState(silent: boolean = false): Promise<void> {
  const savedTerminals = getSavedTerminals();

  if (!savedTerminals || savedTerminals.length === 0) {
    if (!silent) {
      vscode.window.showWarningMessage('Brak zapisanych terminali');
    }
    return;
  }

  // W trybie silent - pokaz tylko wybor, bez otwierania
  if (silent) {
    // Przy auto-restore nie otwieraj automatycznie - czekaj na wybor usera
    return;
  }

  // Pokaz wybor terminali z kolorami
  const colorEmojis: Record<string, string> = {
    'terminal.ansiRed': '🔴',
    'terminal.ansiGreen': '🟢',
    'terminal.ansiBlue': '🔵',
    'terminal.ansiYellow': '🟡',
    'terminal.ansiMagenta': '🟣',
    'terminal.ansiCyan': '🔵'
  };

  const items = savedTerminals.map((t, idx) => ({
    label: `${colorEmojis[t.color || ''] || '⚪'} ${t.name}`,
    description: t.cwd,
    picked: idx < 3, // domyslnie pierwsze 3 zaznaczone
    index: idx
  }));

  const selected = await vscode.window.showQuickPick(items, {
    canPickMany: true,
    placeHolder: 'Wybierz terminale do otwarcia',
    title: 'Przywroc terminale'
  });

  if (!selected || selected.length === 0) {
    return;
  }

  // Pobierz wybrane terminale
  const selectedTerminals = selected.map(s => savedTerminals[s.index]);

  await openAllTerminalsNormally(selectedTerminals);
  vscode.window.showInformationMessage(`Otwarto ${selectedTerminals.length} terminali`);
}

// Wyczysc zapisany stan
export async function clearTerminalState(): Promise<void> {
  const stateFilePath = getStateFilePath();
  if (!stateFilePath) {
    vscode.window.showWarningMessage('Brak otwartego workspace');
    return;
  }

  if (!fs.existsSync(stateFilePath)) {
    vscode.window.showInformationMessage('Brak zapisanego stanu do usuniecia');
    return;
  }

  try {
    fs.unlinkSync(stateFilePath);
    vscode.window.showInformationMessage('Wyczyszczono zapisany stan terminali');
  } catch (error) {
    vscode.window.showErrorMessage(`Blad usuwania stanu: ${error}`);
  }
}

// Usun wybrane terminale z listy
export async function removeTerminalsFromList(): Promise<void> {
  const stateFilePath = getStateFilePath();
  if (!stateFilePath) {
    vscode.window.showWarningMessage('Brak otwartego workspace');
    return;
  }

  const savedTerminals = getSavedTerminals();
  if (!savedTerminals || savedTerminals.length === 0) {
    vscode.window.showWarningMessage('Brak zapisanych terminali');
    return;
  }

  const colorEmojis: Record<string, string> = {
    'terminal.ansiRed': '🔴',
    'terminal.ansiGreen': '🟢',
    'terminal.ansiBlue': '🔵',
    'terminal.ansiYellow': '🟡',
    'terminal.ansiMagenta': '🟣',
    'terminal.ansiCyan': '🔵'
  };

  const items = savedTerminals.map((t, idx) => ({
    label: `${colorEmojis[t.color || ''] || '⚪'} ${t.name}`,
    description: t.cwd,
    picked: false,
    index: idx
  }));

  const selected = await vscode.window.showQuickPick(items, {
    canPickMany: true,
    placeHolder: 'Wybierz terminale do USUNIECIA z listy',
    title: 'Usun terminale'
  });

  if (!selected || selected.length === 0) {
    return;
  }

  // Usun wybrane terminale
  const indicesToRemove = new Set(selected.map(s => s.index));
  const remainingTerminals = savedTerminals.filter((_, idx) => !indicesToRemove.has(idx));

  // Przenumeruj i przydziel unikalne kolory
  const usedColors = new Set<string>();
  const updatedTerminals = remainingTerminals.map((t, idx) => {
    const color = getColorForName(t.name, usedColors);
    usedColors.add(color);
    return {
      ...t,
      splitIndex: idx,
      color
    };
  });

  const state: TerminalState = {
    version: STATE_VERSION,
    savedAt: new Date().toISOString(),
    terminals: updatedTerminals
  };

  try {
    fs.writeFileSync(stateFilePath, JSON.stringify(state, null, 2), 'utf8');
    vscode.window.showInformationMessage(`Usunieto ${selected.length} terminali. Pozostalo: ${updatedTerminals.length}`);
  } catch (error) {
    vscode.window.showErrorMessage(`Blad zapisu: ${error}`);
  }
}

// Zamknij wybrane terminale (z listy uruchomionych)
export async function closeTerminals(): Promise<void> {
  const terminals = vscode.window.terminals;
  if (terminals.length === 0) {
    vscode.window.showWarningMessage('Brak otwartych terminali');
    return;
  }

  const colorEmojis: Record<string, string> = {
    'terminal.ansiRed': '🔴',
    'terminal.ansiGreen': '🟢',
    'terminal.ansiBlue': '🔵',
    'terminal.ansiYellow': '🟡',
    'terminal.ansiMagenta': '🟣',
    'terminal.ansiCyan': '🔵'
  };

  const items = Array.from(terminals).map((t, idx) => {
    const options = t.creationOptions as vscode.TerminalOptions | undefined;
    const colorKey = options?.color?.id || '';
    const emoji = colorEmojis[colorKey] || '⚪';
    return {
      label: `${emoji} ${t.name}`,
      description: typeof options?.cwd === 'string' ? options.cwd : options?.cwd?.fsPath || '',
      picked: false,
      terminal: t
    };
  });

  const selected = await vscode.window.showQuickPick(items, {
    canPickMany: true,
    placeHolder: 'Wybierz terminale do ZAMKNIECIA',
    title: 'Zamknij terminale'
  });

  if (!selected || selected.length === 0) {
    return;
  }

  for (const item of selected) {
    item.terminal.dispose();
  }

  vscode.window.showInformationMessage(`Zamknieto ${selected.length} terminali`);
}

// Dodaj nowy terminal z kolorem (aby uzyc zamiast recznego tworzenia)
export async function addNewTerminal(): Promise<void> {
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders || workspaceFolders.length === 0) {
    vscode.window.showWarningMessage('Brak workspace folders');
    return;
  }

  // Pokaz wybor folderu
  const items = workspaceFolders.map(f => ({
    label: f.name,
    description: f.uri.fsPath,
    folder: f
  }));

  const selected = await vscode.window.showQuickPick(items, {
    placeHolder: 'Wybierz folder dla nowego terminala',
    title: 'Nowy Terminal'
  });

  if (!selected) {
    return;
  }

  // Przydziel unikalny kolor i ikonke (unikaj z zapisanego stanu)
  const usedColors = new Set<string>();
  const usedIcons = new Set<string>();
  const savedTerminals = getSavedTerminals();
  if (savedTerminals) {
    for (const t of savedTerminals) {
      if (t.color) usedColors.add(t.color);
      if (t.icon) usedIcons.add(t.icon);
    }
  }
  const color = getColorForName(selected.folder.name, usedColors);
  const icon = getIconForName(selected.folder.name, usedIcons);

  const terminal = vscode.window.createTerminal({
    name: selected.folder.name,
    cwd: selected.folder.uri.fsPath,
    color: new vscode.ThemeColor(color),
    iconPath: new vscode.ThemeIcon(icon)
  });

  terminal.show();
  vscode.window.showInformationMessage(`Utworzono terminal: ${selected.folder.name}`);
}

// Logowanie do pliku
function log(msg: string): void {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const logLine = `[${ts}] ${msg}\n`;

  // Log do pliku w .vscode/dynamic-terminal-saver.log
  const folders = vscode.workspace.workspaceFolders;
  if (folders?.length) {
    const logPath = path.join(folders[0].uri.fsPath, '.vscode', 'dynamic-terminal-saver.log');
    try {
      fs.appendFileSync(logPath, logLine, 'utf8');
    } catch { /* ignore */ }
  }
}

// Auto-restore przy starcie VS Code (NIE przy Reload Window)
// Uzywa workspaceState z timestampem zeby wykryc Reload Window
export async function autoRestore(context: vscode.ExtensionContext, delayMs: number = 2000): Promise<void> {
  log(`autoRestore() called, delayMs=${delayMs}`);

  // Sprawdz czy autoRestore bylo wykonane niedawno (Reload Window)
  const RELOAD_THRESHOLD_MS = 60000; // 60 sekund
  const lastAutoRestore = context.workspaceState.get<number>('lastAutoRestoreTimestamp');
  const now = Date.now();

  log(`lastAutoRestore=${lastAutoRestore}, now=${now}, diff=${lastAutoRestore ? now - lastAutoRestore : 'N/A'}ms`);

  if (lastAutoRestore && (now - lastAutoRestore) < RELOAD_THRESHOLD_MS) {
    log('SKIP: Reload Window detected (timestamp < 60s)');
    return;
  }

  // Zapisz timestamp (przed delay zeby uniknac race conditions)
  await context.workspaceState.update('lastAutoRestoreTimestamp', now);
  log(`Timestamp saved: ${now}`);

  // Poczekaj az workspace sie zaladuje
  log(`Waiting ${delayMs}ms...`);
  await new Promise(resolve => setTimeout(resolve, delayMs));

  const savedTerminals = getSavedTerminals();
  log(`Saved terminals: ${savedTerminals?.length || 0}`);
  if (!savedTerminals || savedTerminals.length === 0) {
    log('SKIP: No saved terminals');
    return;
  }

  const existingTerminals = vscode.window.terminals;
  const existingNames = Array.from(existingTerminals).map(t => t.name);
  log(`Existing terminals (${existingTerminals.length}): [${existingNames.join(', ')}]`);

  if (existingTerminals.length === 0) {
    log('ACTION: No terminals exist, creating saved ones');
    await openAllTerminalsNormally(savedTerminals);
    log('DONE: Terminals created');
    return;
  }

  // Sprawdz czy nazwy terminali pasuja do zapisanych (dodatkowe zabezpieczenie)
  const savedNames = new Set(savedTerminals.map(t => t.name.toLowerCase()));
  const existingNamesLower = existingNames.map(n => n.toLowerCase());
  const hasMatchingTerminal = existingNamesLower.some(name => savedNames.has(name));

  log(`Saved names: [${Array.from(savedNames).join(', ')}]`);
  log(`Has matching terminal: ${hasMatchingTerminal}`);

  if (hasMatchingTerminal) {
    log('SKIP: Matching terminals found (persistent/restored)');
    return;
  }

  log('ACTION: Closing default terminals and creating saved ones');
  // Swieze uruchomienie z domyslnymi terminalami (pwsh, PowerShell, cmd)
  // Zamknij domyslne i utworz zapisane
  for (const terminal of existingTerminals) {
    log(`Closing: ${terminal.name}`);
    terminal.dispose();
  }
  await new Promise(resolve => setTimeout(resolve, 300));

  await openAllTerminalsNormally(savedTerminals);
  log('DONE: Terminals created');
}
