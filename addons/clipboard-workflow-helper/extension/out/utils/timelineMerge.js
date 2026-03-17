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
exports.TimelineMerge = void 0;
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
/**
 * Timeline Merge - Node.js script do merge entries.json z manifest
 * Spawned z deactivate() gdy VSCode zamyka się
 */
class TimelineMerge {
    /**
     * Główna funckja merge - wykonywana na startup deactivate
     */
    static async run(manifestPath, extensionPath) {
        this.startTime = Date.now();
        this.logFile = path.join(extensionPath, '.timeline-merge.log');
        this.log('[Merge] Starting...');
        try {
            // 1. Sprawdź czy manifest istnieje
            if (!fs.existsSync(manifestPath)) {
                this.log('[Merge] Manifest not found, exiting');
                return;
            }
            // 2. Załaduj manifest
            const manifest = this.loadManifest(manifestPath);
            if (!manifest) {
                this.log('[Merge] Failed to load manifest');
                return;
            }
            this.log(`[Merge] Manifest loaded with ${Object.keys(manifest.updates).length} entries`);
            // 3. Merge entries - dla każdego entries.json path (2 przebiegi)
            let totalUpdated = 0;
            let totalDeferred = 0;
            for (const entriesPath in manifest.updates) {
                const updates = manifest.updates[entriesPath];
                if (!Array.isArray(updates)) {
                    continue;
                }
                this.log(`[Merge] Processing: ${entriesPath}`);
                // Przebieg 1: czekaj 5s, merge dostępne
                const { updated: updated1, deferred: deferred1 } = await this.mergeEntriesSinglePass(entriesPath, updates, 5000);
                totalUpdated += updated1;
                totalDeferred += deferred1;
                // Jeśli coś zostało - przebieg 2: czekaj 10s na resztę
                if (deferred1 > 0) {
                    this.log(`[Merge] Retry: ${deferred1} entries still deferred, waiting 10s...`);
                    await new Promise(resolve => setTimeout(resolve, 10000));
                    const { updated: updated2, deferred: deferred2 } = await this.mergeEntriesSinglePass(entriesPath, updates, 1000);
                    totalUpdated += updated2;
                    totalDeferred += deferred2;
                }
            }
            this.log(`[Merge] Complete - Updated: ${totalUpdated}, Deferred: ${totalDeferred}`);
            // 4. Cleanup - usuń manifest
            if (totalUpdated > 0 || totalDeferred === 0) {
                // Delete manifest jeśli coś się powiodło lub nic nie było do robienia
                try {
                    fs.unlinkSync(manifestPath);
                    this.log('[Merge] Manifest deleted');
                }
                catch (e) {
                    this.log(`[Merge] Failed to delete manifest: ${e}`);
                }
            }
        }
        catch (error) {
            this.log(`[Merge] Fatal error: ${error}`);
        }
        this.log(`[Merge] Finished in ${Date.now() - this.startTime}ms`);
    }
    /**
     * Załaduj i parse manifest JSON
     */
    static loadManifest(manifestPath) {
        try {
            const content = fs.readFileSync(manifestPath, 'utf-8');
            return JSON.parse(content);
        }
        catch (error) {
            this.log(`[Merge] Failed to load/parse manifest: ${error}`);
            return null;
        }
    }
    /**
     * Czekaj aż entries.json będzie kompletny ze wszystkimi ID z updatów
     * VSCode flush może trwać 1-2s, a ostatnie wpisy mogą być dodawane aż do ostatniej chwili
     */
    static async waitForCompleteEntries(entriesPath, neededIds, maxWaitMs = 30000) {
        const startTime = Date.now();
        const checkInterval = 200;
        const neededIdSet = new Set(neededIds);
        let lastLoggedProgress = 0;
        while (Date.now() - startTime < maxWaitMs) {
            try {
                if (!fs.existsSync(entriesPath)) {
                    await new Promise(resolve => setTimeout(resolve, checkInterval));
                    continue;
                }
                const content = fs.readFileSync(entriesPath, 'utf-8');
                const data = JSON.parse(content);
                const existingIds = new Set(data.entries.map(e => e.id));
                // Sprawdź czy wszystkie potrzebne ID są obecne
                const foundIds = [];
                const missingIds = [];
                for (const id of neededIdSet) {
                    if (existingIds.has(id)) {
                        foundIds.push(id);
                    }
                    else {
                        missingIds.push(id);
                    }
                }
                // Log progress co 5 sekund
                const elapsed = Date.now() - startTime;
                if (elapsed - lastLoggedProgress > 5000) {
                    this.log(`[Merge] Progress: found ${foundIds.length}/${neededIds.length} IDs (missing: [${missingIds.join(', ')}])`);
                    lastLoggedProgress = elapsed;
                }
                if (missingIds.length === 0) {
                    this.log(`[Merge] ✓ All ${neededIds.length} IDs found in entries.json (${elapsed}ms)`);
                    return true;
                }
            }
            catch (e) {
                // JSON parse error lub read error - retry
            }
            await new Promise(resolve => setTimeout(resolve, checkInterval));
        }
        this.log(`[Merge] ✗ Timeout waiting for IDs after ${maxWaitMs}ms. Missing: [${neededIds.join(', ')}]`);
        return false;
    }
    /**
     * Merge updates - jeden przebieg
     * Zwraca count updated i deferred (nie znalezione)
     */
    static async mergeEntriesSinglePass(entriesPath, updates, waitMs = 5000) {
        try {
            // Czekaj aby entries.json się pojawił
            const startWait = Date.now();
            while (Date.now() - startWait < waitMs && !fs.existsSync(entriesPath)) {
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            if (!fs.existsSync(entriesPath)) {
                this.log(`[Merge] entries.json not found after ${waitMs}ms`);
                return { updated: 0, deferred: updates.length };
            }
            // Załaduj entries.json
            const content = fs.readFileSync(entriesPath, 'utf-8');
            const data = JSON.parse(content);
            // Merge updates - tylko dla ID które istnieją
            let updated = 0;
            let deferred = 0;
            for (const update of updates) {
                const entry = data.entries.find(e => e.id === update.fileId);
                if (entry) {
                    if (!entry.source && update.source) {
                        entry.source = update.source;
                        updated++;
                        this.log(`[Merge] ✓ ${update.fileId} → "${update.source}"`);
                    }
                    else {
                        this.log(`[Merge] - ${update.fileId} (skipped)`);
                    }
                }
                else {
                    deferred++;
                    this.log(`[Merge] ⏳ ${update.fileId} (not found, will retry)`);
                }
            }
            // NOWA LOGIKA: Przeskanuj folder - dodaj brakujące ID
            // VSCode może nie dodać niektórych ID do entries.json - dodajemy je sami z manifestu
            try {
                const folderPath = path.dirname(entriesPath);
                const filesInFolder = fs.readdirSync(folderPath);
                const existingIds = new Set(data.entries.map(e => e.id));
                this.log(`[Merge] Scanning folder for missing IDs...`);
                for (const file of filesInFolder) {
                    // Pomiń entries.json, pliki .tmp i pliki bez rozszerzenia
                    if (file === 'entries.json' || file.endsWith('.tmp') || !file.includes('.')) {
                        continue;
                    }
                    // Jeśli plik istnieje ale brakuje go w entries.json
                    if (!existingIds.has(file)) {
                        const update = updates.find(u => u.fileId === file);
                        if (update && update.source) {
                            // Dodaj brakujący wpis
                            data.entries.push({
                                id: file,
                                timestamp: Date.now(),
                                source: update.source
                            });
                            updated++;
                            this.log(`[Merge] ✓ ADDED MISSING: ${file} → "${update.source}"`);
                        }
                        else {
                            this.log(`[Merge] ⚠️ Found file but no manifest data: ${file}`);
                        }
                    }
                }
                if (updated > 0) {
                    this.log(`[Merge] Total to save: ${updated} entries`);
                }
            }
            catch (scanError) {
                this.log(`[Merge] Error scanning folder: ${scanError}`);
            }
            // Zapisz jeśli były zmiany
            if (updated > 0) {
                const tmpPath = entriesPath + '.tmp';
                fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf-8');
                // Atomic rename
                if (fs.existsSync(entriesPath)) {
                    fs.unlinkSync(entriesPath);
                }
                fs.renameSync(tmpPath, entriesPath);
                this.log(`[Merge] ✓ Saved ${updated} entries to entries.json`);
            }
            return { updated, deferred };
        }
        catch (error) {
            this.log(`[Merge] Error in pass: ${error}`);
            return { updated: 0, deferred: updates.length };
        }
    }
    /**
     * Napisz do log file
     */
    static log(message) {
        const timestamp = new Date().toLocaleString();
        const line = `[${timestamp}] ${message}\n`;
        try {
            fs.appendFileSync(this.logFile, line, 'utf-8');
        }
        catch (e) {
            // Fail silently
        }
    }
}
exports.TimelineMerge = TimelineMerge;
TimelineMerge.TIMEOUT_MS = 30000; // 30 sekund max
TimelineMerge.logFile = '';
TimelineMerge.startTime = 0;
// Jeśli skrypt uruchomiony bezpośrednio (node timeline-merge.js)
if (require.main === module) {
    const args = process.argv.slice(2);
    if (args.length < 2) {
        console.error('Usage: node timeline-merge.js <manifestPath> <extensionPath>');
        process.exit(1);
    }
    const manifestPath = args[0];
    const extensionPath = args[1];
    TimelineMerge.run(manifestPath, extensionPath)
        .then(() => {
        process.exit(0);
    })
        .catch(error => {
        console.error('Fatal error:', error);
        process.exit(1);
    });
}
//# sourceMappingURL=timelineMerge.js.map