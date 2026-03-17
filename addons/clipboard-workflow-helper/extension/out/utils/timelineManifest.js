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
exports.TimelineManifest = void 0;
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
/**
 * TimelineManifest - zbiera instrukcje runtime dla bat file'a
 * Runtime: dodaj update do manifestu
 * Deactivate: bat czyta manifest i mergeuje/copy entries.json
 */
class TimelineManifest {
    /**
     * Inicjalizuj TimelineManifest
     */
    static initialize(extensionPath, output) {
        this.manifestPath = path.join(extensionPath, '.timeline-manifest.json');
        this.output = output || null;
        // Załaduj existing manifest jeśli istnieje
        this.loadManifest();
    }
    /**
     * Załaduj istniejący manifest (jeśli istnieje)
     */
    static loadManifest() {
        try {
            if (fs.existsSync(this.manifestPath)) {
                const content = fs.readFileSync(this.manifestPath, 'utf-8');
                this.data = JSON.parse(content);
                if (this.output) {
                    this.output.appendLine(`[Manifest] Loaded existing manifest (${Object.keys(this.data.updates).length} folders)`);
                }
            }
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Manifest] Failed to load existing manifest, starting fresh: ${error}`);
            }
            this.data = {
                timestamp: Date.now(),
                updates: {}
            };
        }
    }
    /**
     * Dodaj update do manifestu (zbieranie instrukcji runtime)
     * historyFolder: np. "40eb624d"
     * fileId: np. "aBcD.md"
     * source: parsed title z komentarza
     * changed: np. "+120/-45"
     */
    static addUpdate(historyFolder, fileId, source, changed) {
        try {
            // Inicjalizuj folder array jeśli nie istnieje
            if (!this.data.updates[historyFolder]) {
                this.data.updates[historyFolder] = [];
            }
            // Sprawdź czy nie ma duplikatu dla tego fileId
            const existing = this.data.updates[historyFolder].find(u => u.fileId === fileId);
            if (existing) {
                // Update istniejące
                existing.source = source;
                existing.changed = changed;
                if (this.output) {
                    this.output.appendLine(`[Manifest] Updated: ${fileId} → "${source}"`);
                }
            }
            else {
                // Dodaj nowe
                this.data.updates[historyFolder].push({
                    fileId,
                    source,
                    changed
                });
                if (this.output) {
                    this.output.appendLine(`[Manifest] Added: ${historyFolder}/${fileId} → "${source}" (${changed})`);
                }
            }
            // Zaktualizuj timestamp
            this.data.timestamp = Date.now();
            // Zapisz do pliku
            this.save();
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Manifest] addUpdate error: ${error}`);
            }
        }
    }
    /**
     * Zapisz manifest do .timeline-manifest.json
     */
    static save() {
        try {
            const content = JSON.stringify(this.data, null, 2);
            fs.writeFileSync(this.manifestPath, content, 'utf-8');
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Manifest] Failed to save manifest: ${error}`);
            }
        }
    }
    /**
     * Wyczyść manifest (po udanym merge'u w bat)
     * Bat file powinien wywoływać to (poprzez Node.js script jeśli potrzeba)
     */
    static clear() {
        try {
            if (fs.existsSync(this.manifestPath)) {
                fs.unlinkSync(this.manifestPath);
                if (this.output) {
                    this.output.appendLine(`[Manifest] Cleared`);
                }
            }
            this.data = {
                timestamp: Date.now(),
                updates: {}
            };
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[Manifest] Failed to clear manifest: ${error}`);
            }
        }
    }
    /**
     * Pobierz path do manifestu (dla bat file'a)
     */
    static getManifestPath() {
        return this.manifestPath;
    }
    /**
     * Czy manifest ma dane do mergeowania?
     */
    static hasUpdates() {
        return Object.keys(this.data.updates).length > 0;
    }
}
exports.TimelineManifest = TimelineManifest;
TimelineManifest.manifestPath = '';
TimelineManifest.output = null;
TimelineManifest.data = {
    timestamp: Date.now(),
    updates: {}
};
//# sourceMappingURL=timelineManifest.js.map