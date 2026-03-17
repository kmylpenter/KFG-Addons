"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AutoBackupManager = void 0;
const timelineManager_1 = require("./timelineManager");
const titleParser_1 = require("./titleParser");
/**
 * AutoBackupManager - automatyczny backup przy każdym save z debounce
 * Zabezpiecza przed utratą zmian gdy Claude Code edytuje pliki
 */
class AutoBackupManager {
    /**
     * Inicjalizuj AutoBackupManager
     */
    static initialize(output) {
        this.output = output || null;
        if (this.output) {
            this.output.appendLine(`[AutoBackup] Initialized (debounce: ${this.DEBOUNCE_MS}ms)`);
        }
    }
    /**
     * Obsłuż save dokumentu - utwórz backup jeśli minął debounce
     */
    static async handleSave(document) {
        const uri = document.uri.toString();
        const now = Date.now();
        const last = this.lastBackup.get(uri) || 0;
        // Debounce - skip jeśli ostatni backup < 30s temu
        if (now - last < this.DEBOUNCE_MS) {
            if (this.output) {
                const remaining = Math.round((this.DEBOUNCE_MS - (now - last)) / 1000);
                this.output.appendLine(`[AutoBackup] Skipped (debounce) - ${remaining}s left`);
            }
            return;
        }
        // Utwórz backup
        this.lastBackup.set(uri, now);
        // Parsuj tytuł z komentarza w pliku (np. // ==Save: Opis==)
        const parseResult = titleParser_1.TitleParser.parseTitle(document);
        const label = parseResult.title || 'Claude Backup';
        if (this.output) {
            this.output.appendLine(`[AutoBackup] Creating backup for ${document.fileName}`);
            if (parseResult.title) {
                this.output.appendLine(`[AutoBackup] Using title from comment: "${parseResult.title}"`);
            }
        }
        try {
            // skipSave=true → NIE wywołuje files.save, tworzy folder History samodzielnie
            // To zapobiega modyfikacji pliku podczas gdy Claude Code go edytuje
            await timelineManager_1.TimelineManager.addTimelineEntry(document, label, true);
            if (this.output) {
                this.output.appendLine(`[AutoBackup] Backup created: "${label}"`);
            }
        }
        catch (error) {
            if (this.output) {
                this.output.appendLine(`[AutoBackup] Error: ${error}`);
            }
        }
    }
    /**
     * Reset timer dla URI - wywoływane po Ctrl+A+C (ręczny backup)
     * Zapobiega duplikatom: po ręcznym backup nie będzie auto-backup przez 30s
     */
    static resetTimer(uri) {
        this.lastBackup.set(uri, Date.now());
        if (this.output) {
            this.output.appendLine(`[AutoBackup] Timer reset for manual backup`);
        }
    }
}
exports.AutoBackupManager = AutoBackupManager;
// Map: uri → last backup timestamp
AutoBackupManager.lastBackup = new Map();
AutoBackupManager.DEBOUNCE_MS = 30000; // 30 sekund
AutoBackupManager.output = null;
//# sourceMappingURL=autoBackupManager.js.map