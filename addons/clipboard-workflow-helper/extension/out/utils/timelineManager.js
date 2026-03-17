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
exports.TimelineManager = void 0;
const vscode = __importStar(require("vscode"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
const titleParser_1 = require("./titleParser");
const entriesJsonUpdater_1 = require("./entriesJsonUpdater");
const titleCache_1 = require("./titleCache");
const timelineManifest_1 = require("./timelineManifest");
class TimelineManager {
    /**
     * Inicjalizuj TimelineManager z kontekstem extension
     */
    static initialize(context, output) {
        this.output = output || null;
        this.cachePath = path.join(context.extensionPath, 'timeline-cache.json');
        this.configPath = path.join(context.extensionPath, 'timeline-config.json');
        // ZMIANA: TitleCache teraz używa globalStoragePath (AppData, bezpieczny)
        // zamiast extensionPath (może być symlinkowany na Zoho WorkDrive)
        titleCache_1.TitleCache.initialize(context.globalStoragePath);
        this.loadOrCreateConfig();
        this.recoverMissingTitles(); // Recovery logic dla entries bez title
        this.startBackgroundTask(); // Background task - co 10 minut próbuj update entries
        this.watchEntriesJsonFiles(); // Watch entries.json dla live refresh Timeline
    }
    /**
     * Watch entries.json files - gdy się zmienią, trigger VSCode refresh
     * VSCode Timeline powinien się auto-update na zmiany entries.json
     */
    static watchEntriesJsonFiles() {
        if (!fs.existsSync(this.historyPath)) {
            return;
        }
        try {
            const watcher = vscode.workspace.createFileSystemWatcher(path.join(this.historyPath, '*/entries.json'));
            watcher.onDidChange(() => {
                // entries.json się zmienił - VSCode Timeline powinien odświeżyć się automatycznie
                // VSCode monitoruje LocalHistory folder, więc detection powinien być automatyczny
                if (this.output) {
                    this.output.appendLine(`[Timeline] entries.json changed - VSCode should auto-refresh Timeline`);
                }
            });
            watcher.onDidCreate(() => {
                if (this.output) {
                    this.output.appendLine(`[Timeline] entries.json created - Timeline should be updated`);
                }
            });
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Timeline] watchEntriesJsonFiles error: ${error}`);
            }
        }
    }
    /**
     * Background task - co N minut sprawdź czy są entries bez source
     * i spróbuj je update z title-cache (konfigurowalny interval)
     */
    static startBackgroundTask() {
        // Czytaj interval z VSCode settings (domyślnie 10 minut)
        const config = vscode.workspace.getConfiguration('clipboardHelper');
        let intervalMinutes = config.get('backgroundTaskIntervalMinutes', 10);
        // Walidacja - min 1 minuta, max 60 minut
        if (intervalMinutes < 1) {
            intervalMinutes = 1;
        }
        if (intervalMinutes > 60) {
            intervalMinutes = 60;
        }
        const intervalMs = intervalMinutes * 60 * 1000;
        if (this.output) {
            this.output.appendLine(`[Timeline] Background task interval: ${intervalMinutes} minute(s) (${intervalMs}ms)`);
        }
        // Uruchom first check po 30 sekundach (daj VSCode czas na startup)
        setTimeout(() => {
            if (this.output) {
                this.output.appendLine(`[Timeline] First background task check...`);
            }
            this.recoverMissingTitles();
        }, 30000);
        // Potem co N minut
        this.backgroundTaskInterval = setInterval(() => {
            if (this.output) {
                this.output.appendLine(`[Timeline] Background task check (every ${intervalMinutes}min)...`);
            }
            this.recoverMissingTitles();
        }, intervalMs);
    }
    /**
     * Załaduj lub stwórz plik konfiguracji
     * Fallback logic: spróbuj wszystkie paths, error tylko jeśli żadna nie valid
     */
    static loadOrCreateConfig() {
        try {
            const hostname = os.hostname().toUpperCase();
            const appData = process.env.APPDATA || '';
            const defaultPath = path.join(appData, 'Code', 'User', 'History');
            if (fs.existsSync(this.configPath)) {
                const content = fs.readFileSync(this.configPath, 'utf-8');
                let config = JSON.parse(content);
                // Migracja ze starego formatu (historyPath) na nowy (computers)
                if (config.historyPath && !config.computers) {
                    config = {
                        description: 'Konfiguracja VSCode History dla różnych komputerów. Dodaj więcej komputerów do "computers".',
                        computers: {
                            [hostname]: config.historyPath
                        },
                        defaultPath: config.historyPath
                    };
                    fs.writeFileSync(this.configPath, JSON.stringify(config, null, 2));
                }
                // Spróbuj paths w fallback order: hostname → defaultPath → computed default
                const pathsToTry = [
                    config.computers?.[hostname],
                    config.defaultPath,
                    defaultPath
                ].filter(p => p !== undefined && p !== null);
                let foundValid = false;
                for (const tryPath of pathsToTry) {
                    if (fs.existsSync(tryPath)) {
                        this.historyPath = tryPath;
                        foundValid = true;
                        if (this.output) {
                            this.output.appendLine(`[Timeline] Using History path: ${tryPath}`);
                        }
                        break;
                    }
                }
                if (!foundValid) {
                    this.showConfigError(pathsToTry);
                }
            }
            else {
                // Utwórz config z domyślną ścieżką
                const config = {
                    description: 'Konfiguracja VSCode History dla różnych komputerów. Dodaj więcej komputerów do "computers".',
                    computers: {
                        [hostname]: defaultPath
                    },
                    defaultPath: defaultPath
                };
                fs.writeFileSync(this.configPath, JSON.stringify(config, null, 2));
                // Spróbuj domyślną ścieżkę
                if (fs.existsSync(defaultPath)) {
                    this.historyPath = defaultPath;
                }
                else {
                    this.showConfigError([defaultPath]);
                }
            }
        }
        catch (error) {
            this.showConfigError([]);
        }
    }
    /**
     * Pokaż error tylko jeśli żadna ścieżka nie jest valid
     */
    static showConfigError(attemptedPaths = []) {
        const pathsStr = attemptedPaths.length > 0
            ? `\n\nProbowane ścieżki:\n${attemptedPaths.join('\n')}`
            : '';
        vscode.window.showErrorMessage(`Nie znaleziono żadnej ścieżki VSCode History.${pathsStr}`, 'Otwórz Config').then(choice => {
            if (choice === 'Otwórz Config') {
                vscode.commands.executeCommand('vscode.open', vscode.Uri.file(this.configPath));
            }
        });
    }
    /**
     * Hash string używając DOKŁADNEGO algorytmu VSCode (z vs/base/common/hash.ts)
     * VSCode używa tego do generowania nazw folderów History
     */
    static hashString(str) {
        // VSCode numberHash: ((initialHashVal << 5) - initialHashVal) + val
        const numberHash = (val, initialHashVal) => {
            return (((initialHashVal << 5) - initialHashVal) + val) | 0;
        };
        // VSCode stringHash: starts with 149417, then hashes each char
        let hashVal = 0;
        hashVal = numberHash(149417, hashVal);
        for (let i = 0; i < str.length; i++) {
            hashVal = numberHash(str.charCodeAt(i), hashVal);
        }
        // Convert to hex, negative values have minus prefix
        if (hashVal < 0) {
            return '-' + Math.abs(hashVal).toString(16);
        }
        return hashVal.toString(16);
    }
    /**
     * Znajdź folder History dla danego resource URI (czytając entries.json)
     */
    static findHistoryFolderByResource(resourceUri) {
        try {
            if (!fs.existsSync(this.historyPath)) {
                return null;
            }
            const hashFolders = fs.readdirSync(this.historyPath);
            for (const hashFolder of hashFolders) {
                const entriesPath = path.join(this.historyPath, hashFolder, 'entries.json');
                try {
                    if (!fs.existsSync(entriesPath)) {
                        continue;
                    }
                    const content = fs.readFileSync(entriesPath, 'utf-8');
                    const data = JSON.parse(content);
                    if (data.resource === resourceUri) {
                        return hashFolder;
                    }
                }
                catch (e) {
                    // Skip folder on parse error
                }
            }
            return null;
        }
        catch (error) {
            return null;
        }
    }
    /**
     * Znajdź lub stwórz folder History dla dokumentu
     * Jeśli folder nie istnieje - tworzy go wraz z entries.json
     */
    static getOrCreateHistoryFolder(document) {
        try {
            const resource = document.uri.toString();
            // 1. Sprawdź cache
            if (this.cache && this.cache.lastResource === resource) {
                const folderPath = path.join(this.historyPath, this.cache.lastHashFolder);
                if (fs.existsSync(folderPath)) {
                    return { folderPath, hashFolder: this.cache.lastHashFolder, isNew: false };
                }
            }
            // 2. Szukaj istniejącego folderu
            const existingFolder = this.findHistoryFolderByResource(resource);
            if (existingFolder) {
                const folderPath = path.join(this.historyPath, existingFolder);
                this.cache = { lastHashFolder: existingFolder, lastResource: resource, lastUpdated: Date.now() };
                return { folderPath, hashFolder: existingFolder, isNew: false };
            }
            // 3. Stwórz nowy folder (hash z resource URI)
            const hashFolder = this.hashString(resource);
            const folderPath = path.join(this.historyPath, hashFolder);
            if (this.output) {
                this.output.appendLine(`[Timeline] Creating new History folder: ${hashFolder}`);
            }
            if (!fs.existsSync(folderPath)) {
                fs.mkdirSync(folderPath, { recursive: true });
            }
            // Stwórz entries.json
            const entriesPath = path.join(folderPath, 'entries.json');
            if (!fs.existsSync(entriesPath)) {
                const entriesData = { version: 1, resource: resource, entries: [] };
                fs.writeFileSync(entriesPath, JSON.stringify(entriesData, null, 2), 'utf-8');
            }
            this.cache = { lastHashFolder: hashFolder, lastResource: resource, lastUpdated: Date.now() };
            fs.writeFileSync(this.cachePath, JSON.stringify(this.cache));
            return { folderPath, hashFolder, isNew: true };
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Timeline] getOrCreateHistoryFolder error: ${error}`);
            }
            return null;
        }
    }
    /**
     * Dodaj entry do entries.json bezpośrednio
     */
    static addEntryToEntriesJson(entriesPath, backupId, timestamp, source) {
        try {
            if (!fs.existsSync(entriesPath)) {
                return false;
            }
            const content = fs.readFileSync(entriesPath, 'utf-8');
            const data = JSON.parse(content);
            const newEntry = { id: backupId, timestamp: timestamp };
            if (source) {
                newEntry.source = source;
            }
            data.entries.push(newEntry);
            // Atomic write
            const tmpPath = entriesPath + '.tmp';
            fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf-8');
            if (fs.existsSync(entriesPath)) {
                fs.unlinkSync(entriesPath);
            }
            fs.renameSync(tmpPath, entriesPath);
            return true;
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Timeline] addEntryToEntriesJson error: ${error}`);
            }
            return false;
        }
    }
    /**
     * Wygeneruj losowy 4-znakowy ID (jak VSCode)
     */
    static generateRandomId() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        let id = '';
        for (let i = 0; i < 4; i++) {
            id += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        this.lastGeneratedId = id;
        return id;
    }
    /**
     * Czekaj na najnowszy plik w którymkolwiek folderze History (mtime < 10s)
     */
    static async waitForNewestFile(maxWaitMs = 15000) {
        const startTime = Date.now();
        const checkInterval = 200; // Sprawdzaj co 200ms
        while (Date.now() - startTime < maxWaitMs) {
            try {
                const dirs = fs.readdirSync(this.historyPath);
                let newestDir = null;
                let newestFileTime = 0;
                for (const dir of dirs) {
                    const dirPath = path.join(this.historyPath, dir);
                    try {
                        const stat = fs.statSync(dirPath);
                        if (!stat.isDirectory())
                            continue;
                        // Szukaj newest FILE wewnątrz folderu
                        try {
                            const files = fs.readdirSync(dirPath);
                            for (const file of files) {
                                const filePath = path.join(dirPath, file);
                                try {
                                    const fileStat = fs.statSync(filePath);
                                    if (fileStat.isFile() && fileStat.mtimeMs > newestFileTime) {
                                        newestFileTime = fileStat.mtimeMs;
                                        newestDir = dir;
                                    }
                                }
                                catch (e) {
                                    // Skip file
                                }
                            }
                        }
                        catch (e) {
                            // Skip folder
                        }
                    }
                    catch (e) {
                        // Skip
                    }
                }
                // Jeśli znalezliśmy plik starszy niż 10 sekund
                if (newestDir && Date.now() - newestFileTime < 10000) {
                    if (this.output) {
                        this.output.appendLine(`[Timeline] Found newest file in folder: ${newestDir} (${Math.round(Date.now() - newestFileTime)}ms ago)`);
                    }
                    return newestDir;
                }
            }
            catch (error) {
                // Retry
            }
            // Czekaj przed następnym sprawdzeniem
            await new Promise(resolve => setTimeout(resolve, checkInterval));
        }
        return null;
    }
    /**
     * Zapisz backup plik do folderu History
     */
    static writeBackupToFolder(folderPath, document) {
        try {
            const ext = path.extname(document.uri.fsPath) || '.md';
            const backupFileName = this.generateRandomId() + ext;
            const backupPath = path.join(folderPath, backupFileName);
            const content = document.getText();
            fs.writeFileSync(backupPath, content, 'utf-8');
            return true;
        }
        catch (error) {
            return false;
        }
    }
    /**
     * Schedule background check dla konkretnego resource
     * Uruchamia się co interval_minutes, ALE TYLKO dla tego konkretnego pliku
     */
    static scheduleBackgroundCheckForResource(resourceUri, entriesPath, backupId, title) {
        // Jeśli już mamy timer dla tego resource, nie twórz duplikat
        if (this.pendingTitles.has(resourceUri)) {
            return;
        }
        const config = vscode.workspace.getConfiguration('clipboardHelper');
        let intervalMinutes = config.get('backgroundTaskIntervalMinutes', 10);
        if (intervalMinutes < 1)
            intervalMinutes = 1;
        if (intervalMinutes > 60)
            intervalMinutes = 60;
        const intervalMs = intervalMinutes * 60 * 1000;
        if (this.output) {
            this.output.appendLine(`[Timeline] Scheduled background check for resource (retry every ${intervalMinutes}min)`);
        }
        // Start timer dla tego resource
        const timer = setInterval(async () => {
            try {
                const success = await this.tryUpdateEntryForResource(entriesPath, backupId, title);
                if (success) {
                    // Zaktualizowano successfully - wyczyść timer
                    clearInterval(timer);
                    this.pendingTitles.delete(resourceUri);
                    if (this.output) {
                        this.output.appendLine(`[Timeline] Background check succeeded for resource, timer cleared`);
                    }
                }
            }
            catch (error) {
                if (this.output) {
                    this.output.appendLine(`[Timeline] Background check error: ${error}`);
                }
            }
        }, intervalMs);
        // Zapisz timer aby móc go wyczyścić
        this.pendingTitles.set(resourceUri, {
            title,
            entriesPath,
            backupId,
            timer
        });
    }
    /**
     * Try update entry dla konkretnego resource (helper dla background check)
     */
    static async tryUpdateEntryForResource(entriesPath, backupId, title) {
        try {
            if (!fs.existsSync(entriesPath)) {
                return false;
            }
            const content = fs.readFileSync(entriesPath, 'utf-8');
            const data = JSON.parse(content);
            const entry = data.entries.find(e => e.id === backupId);
            if (!entry) {
                return false;
            }
            // Update source field
            if (!entry.source && title) {
                entry.source = title;
                // Atomic write
                const tmpPath = entriesPath + '.tmp';
                fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf-8');
                if (fs.existsSync(entriesPath)) {
                    fs.unlinkSync(entriesPath);
                }
                fs.renameSync(tmpPath, entriesPath);
                if (this.output) {
                    this.output.appendLine(`[Timeline] Background check: successfully updated source for ${backupId}`);
                }
                return true;
            }
            return false;
        }
        catch (error) {
            return false;
        }
    }
    /**
     * Recover missing titles - przy startup sprawdź czy są entries bez source field
     * które możemy uzupełnić z title-cache.json
     */
    static recoverMissingTitles() {
        try {
            // Wyczyść stare cache entries (starsze niż 7 dni)
            titleCache_1.TitleCache.cleanOldEntries();
            // Czytaj wszystkie entries z wszystkich folderów History
            if (!fs.existsSync(this.historyPath)) {
                return;
            }
            const hashFolders = fs.readdirSync(this.historyPath);
            for (const hashFolder of hashFolders) {
                const entriesPath = path.join(this.historyPath, hashFolder, 'entries.json');
                try {
                    if (!fs.existsSync(entriesPath)) {
                        continue;
                    }
                    const content = fs.readFileSync(entriesPath, 'utf-8');
                    const data = JSON.parse(content);
                    let hasChanges = false;
                    // Sprawdź każdy entry
                    for (const entry of data.entries) {
                        // Jeśli entry ma source - skip (już ma title)
                        if (entry.source) {
                            continue;
                        }
                        // Szukaj cached title dla tego resource
                        const cachedTitle = titleCache_1.TitleCache.getTitle(data.resource);
                        if (cachedTitle && cachedTitle.backupId === entry.id) {
                            // Znaleźliśmy cached title dla tego entry
                            entry.source = cachedTitle.title;
                            hasChanges = true;
                            if (this.output) {
                                this.output.appendLine(`[Timeline] Recovered title from cache: "${cachedTitle.title}" (${entry.id})`);
                            }
                            // Wyczyść cache po recover
                            titleCache_1.TitleCache.clearTitle(data.resource);
                        }
                    }
                    // Zapisz jeśli były zmiany
                    if (hasChanges) {
                        try {
                            const tmpPath = entriesPath + '.tmp';
                            const newContent = JSON.stringify(data, null, 2);
                            fs.writeFileSync(tmpPath, newContent, 'utf-8');
                            if (fs.existsSync(entriesPath)) {
                                fs.unlinkSync(entriesPath);
                            }
                            fs.renameSync(tmpPath, entriesPath);
                            if (this.output) {
                                this.output.appendLine(`[Timeline] Successfully recovered titles in ${hashFolder}`);
                            }
                        }
                        catch (writeError) {
                            if (this.output) {
                                this.output.appendLine(`[Timeline] Failed to recover titles: ${writeError}`);
                            }
                        }
                    }
                }
                catch (folderError) {
                    // Skip this folder on error
                }
            }
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Timeline] recoverMissingTitles error: ${error}`);
            }
        }
    }
    /**
     * Asynchronicznie aktualizuj entries.json z parsed title z komentarza w pliku
     */
    static async scheduleEntriesJsonUpdate(document, entriesPath, backupId) {
        try {
            // 1. Parse title z komentarza
            const parseResult = titleParser_1.TitleParser.parseTitle(document);
            if (this.output && parseResult.title) {
                this.output.appendLine(`[Timeline] Parsed title: "${parseResult.title}" (line ${parseResult.lineNumber})`);
                // Zapisz title do cache na wypadek gdyby VSCode się zamknął zanim skończymy update
                titleCache_1.TitleCache.saveTitle(document.uri.toString(), parseResult.title, backupId);
                // Dodaj do Timeline Manifest dla Node.js script
                // entriesPath: C:\...\History\40eb624d\entries.json (PEŁNA ŚCIEŻKA!)
                // backupId: VSCode przechowuje ID z extensionem! (np. Numc.dg, jlxP.js)
                const ext = path.extname(document.uri.fsPath) || '';
                const backupIdWithExt = backupId + ext;
                const changeSummary = ''; // TODO: Get from ChangeTracker jeśli potrzebne
                timelineManifest_1.TimelineManifest.addUpdate(entriesPath, backupIdWithExt, parseResult.title, changeSummary);
            }
            // 2. Update entries.json (async z delay wbudowanym)
            const success = await entriesJsonUpdater_1.EntriesJsonUpdater.updateEntry(entriesPath, backupId, parseResult.title, this.output);
            if (this.output) {
                this.output.appendLine(`[Timeline] entries.json update: ${success ? 'success' : 'failed'}`);
            }
            // 3. Jeśli update się powiódł, wyczyść cache (już nie potrzebny)
            if (success && parseResult.title) {
                titleCache_1.TitleCache.clearTitle(document.uri.toString());
                this.pendingTitles.delete(document.uri.toString());
            }
            // 4. Jeśli update FAILNĄŁ ale title istnieje - zaplanuj background retry dla tego resource
            if (!success && parseResult.title) {
                this.scheduleBackgroundCheckForResource(document.uri.toString(), entriesPath, backupId, parseResult.title);
            }
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Timeline] scheduleEntriesJsonUpdate error: ${error}`);
            }
        }
    }
    /**
     * Dodaj wpis Timeline dla dokumentu
     * @param skipSave - jeśli true, NIE wywołuj files.save (dla auto-backup z FileSystemWatcher)
     *                   Zamiast tego tworzy folder History samodzielnie
     */
    static async addTimelineEntry(document, label, skipSave = false) {
        try {
            const resource = document.uri.toString();
            if (this.output) {
                this.output.appendLine(`[Timeline] Starting (skipSave=${skipSave})`);
            }
            // ===== NOWY FLOW: skipSave=true (auto-backup) =====
            // Nie wywołuje files.save - tworzy folder History samodzielnie
            if (skipSave) {
                const folderResult = this.getOrCreateHistoryFolder(document);
                if (!folderResult) {
                    if (this.output) {
                        this.output.appendLine(`[Timeline] Failed to get/create History folder`);
                    }
                    return false;
                }
                // Zapisz backup plik
                const success = this.writeBackupToFolder(folderResult.folderPath, document);
                if (!success) {
                    if (this.output) {
                        this.output.appendLine(`[Timeline] Failed to write backup file`);
                    }
                    return false;
                }
                // Parsuj tytuł z komentarza
                const parseResult = titleParser_1.TitleParser.parseTitle(document);
                const title = parseResult.title || label;
                const ext = path.extname(document.uri.fsPath) || '';
                const backupIdWithExt = this.lastGeneratedId + ext;
                // Dodaj entry bezpośrednio do entries.json
                const entriesPath = path.join(folderResult.folderPath, 'entries.json');
                this.addEntryToEntriesJson(entriesPath, backupIdWithExt, Date.now(), title);
                // Dodaj do manifest dla timelineMerge (backup strategy)
                timelineManifest_1.TimelineManifest.addUpdate(entriesPath, backupIdWithExt, title, '');
                // Cache title
                if (title) {
                    titleCache_1.TitleCache.saveTitle(resource, title, backupIdWithExt);
                }
                if (this.output) {
                    this.output.appendLine(`[Timeline] Auto-backup success: ${backupIdWithExt} → "${title}"`);
                }
                return true;
            }
            // ===== STARY FLOW: skipSave=false (Ctrl+A+C, manual) =====
            // Sprawdzić czy jest cache
            if (this.cache && this.cache.lastResource === resource && Date.now() - this.cache.lastUpdated < 60000) {
                // Cache istnieje i jest świeży - używaj go (subsequent Ctrl+A+C)
                const folderPath = path.join(this.historyPath, this.cache.lastHashFolder);
                if (this.output) {
                    this.output.appendLine(`[Timeline] Using cached folder: ${this.cache.lastHashFolder}`);
                }
                if (fs.existsSync(folderPath)) {
                    const success = this.writeBackupToFolder(folderPath, document);
                    if (success) {
                        // Schedule async update entries.json
                        const entriesPath = path.join(folderPath, 'entries.json');
                        this.scheduleEntriesJsonUpdate(document, entriesPath, this.lastGeneratedId);
                        if (this.output) {
                            this.output.appendLine(`[Timeline] Backup written successfully`);
                        }
                        return true;
                    }
                }
            }
            // Brak cache lub cache przeterminowany - first Ctrl+A+C
            if (this.output) {
                this.output.appendLine(`[Timeline] Waiting for VSCode to create History folder...`);
            }
            // Poproś VSCode o stworzenie wpisu (dialog Save)
            await vscode.commands.executeCommand('workbench.action.files.save');
            if (this.output) {
                this.output.appendLine(`[Timeline] Save executed, waiting for History folder...`);
            }
            // Czekaj na pojawienie się nowego folderu
            const newestFolder = await this.waitForNewestFile();
            if (!newestFolder) {
                if (this.output) {
                    this.output.appendLine(`[Timeline] No new folder found in History`);
                }
                return false;
            }
            if (this.output) {
                this.output.appendLine(`[Timeline] Found new folder: ${newestFolder}`);
            }
            // Cache'uj folder na przyszłość
            this.cache = {
                lastHashFolder: newestFolder,
                lastResource: resource,
                lastUpdated: Date.now()
            };
            fs.writeFileSync(this.cachePath, JSON.stringify(this.cache));
            // Zapisz backup file
            const folderPath = path.join(this.historyPath, newestFolder);
            const backupSuccess = this.writeBackupToFolder(folderPath, document);
            // Schedule async update entries.json
            if (backupSuccess) {
                const entriesPath = path.join(folderPath, 'entries.json');
                this.scheduleEntriesJsonUpdate(document, entriesPath, this.lastGeneratedId);
            }
            if (this.output) {
                this.output.appendLine(`[Timeline] Backup ${backupSuccess ? 'success' : 'failed'}`);
            }
            return backupSuccess;
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Timeline] Error: ${error}`);
            }
            return false;
        }
    }
}
exports.TimelineManager = TimelineManager;
TimelineManager.historyPath = '';
TimelineManager.output = null;
TimelineManager.cachePath = '';
TimelineManager.configPath = '';
TimelineManager.cache = null;
TimelineManager.lastGeneratedId = '';
TimelineManager.backgroundTaskInterval = null;
TimelineManager.pendingTitles = new Map(); // resourceUri → pending title
//# sourceMappingURL=timelineManager.js.map