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
exports.EntriesJsonUpdater = void 0;
const fs = __importStar(require("fs"));
class EntriesJsonUpdater {
    /**
     * Update entries.json - BUT CAREFUL!
     * VSCode flushuje entries.json z memory przy shutdown i NADPISUJE nasze zmiany
     * Strategy: NIE pisz entries.json w trakcie sesji!
     *
     * Title przechowujemy w cache (TitleCache), recovery logic doda go przy następnym starcie VSCode
     * Entry pojawi się w entries.json gdy VSCode shutdown'uje i flush'uje swoją memory
     */
    static async updateEntry(entriesPath, backupId, title, output) {
        try {
            if (output) {
                output.appendLine(`[Timeline] Title cached - will be recovered on next VSCode restart`);
            }
            // NIE pisz entries.json!
            // VSCode go nadpisze przy shutdown, our changes will be lost
            // Title jest już zapisany w cache przez scheduleEntriesJsonUpdate()
            // Recovery logic przy siguiente VSCode start doda title z cache
            return true; // Success - title w cache, recovery będzie działać
        }
        catch (error) {
            if (output) {
                output.appendLine(`[Timeline] updateEntry error: ${error}`);
            }
            return false;
        }
    }
    /**
     * Ekstrahuj resource URI z entries.json path
     * Path: C:\...\History\-3d6f15c3\entries.json
     * Resource: file:///c%3A/Users/.../file.dg
     * (Nie mamy resource w tym punkcie, więc placeholder)
     */
    static extractResourceFromPath(entriesPath) {
        // Placeholder - VSCode sam to ustalił, my to zostawiamy jako unknow
        // W praktyce VSCode to update'uje przy shutdown
        return 'file:///unknown';
    }
    /**
     * Czekaj aż VSCode doda wpis z danym ID do entries.json
     * Polling co 100ms, max 5 sekund (VSCode zwykle dodaje wpis w 1-2s)
     */
    static async waitForEntry(entriesPath, backupId, output) {
        const maxWaitMs = 5000;
        const checkInterval = 100;
        const startTime = Date.now();
        if (output) {
            output.appendLine(`[Timeline] Waiting for VSCode to add entry ${backupId} to entries.json...`);
        }
        while (Date.now() - startTime < maxWaitMs) {
            try {
                const entriesData = await this.readEntriesJson(entriesPath, output);
                if (entriesData) {
                    const entry = entriesData.entries.find(e => e.id === backupId);
                    if (entry) {
                        if (output) {
                            const elapsed = Date.now() - startTime;
                            output.appendLine(`[Timeline] Entry found after ${elapsed}ms`);
                        }
                        return true;
                    }
                }
            }
            catch (error) {
                // Ignore read errors during polling
            }
            // Czekaj przed następnym sprawdzeniem
            await new Promise(resolve => setTimeout(resolve, checkInterval));
        }
        if (output) {
            output.appendLine(`[Timeline] Timeout waiting for entry (${maxWaitMs}ms)`);
        }
        return false;
    }
    /**
     * Czytaj entries.json z retry logic
     */
    static async readEntriesJson(entriesPath, output) {
        const maxRetries = 3;
        const retryDelayMs = 500;
        for (let attempt = 0; attempt < maxRetries; attempt++) {
            try {
                if (!fs.existsSync(entriesPath)) {
                    if (output && attempt === 0) {
                        output.appendLine(`[Timeline] entries.json not found: ${entriesPath}`);
                    }
                    return null;
                }
                const content = fs.readFileSync(entriesPath, 'utf-8');
                const data = JSON.parse(content);
                if (output && attempt > 0) {
                    output.appendLine(`[Timeline] Successfully read entries.json after ${attempt} retries`);
                }
                return data;
            }
            catch (error) {
                const isLastAttempt = attempt === maxRetries - 1;
                if (error instanceof SyntaxError) {
                    // JSON corrupted - nie retry, just fail
                    if (output) {
                        output.appendLine(`[Timeline] entries.json corrupted: ${error.message}`);
                    }
                    return null;
                }
                // File locked or other IO error - retry
                if (!isLastAttempt) {
                    if (output) {
                        output.appendLine(`[Timeline] Failed to read entries.json, retrying (${attempt + 1}/${maxRetries})...`);
                    }
                    await new Promise(resolve => setTimeout(resolve, retryDelayMs));
                    continue;
                }
                // Last attempt failed
                if (output) {
                    output.appendLine(`[Timeline] Failed to read entries.json after ${maxRetries} retries: ${error}`);
                }
                return null;
            }
        }
        return null;
    }
    /**
     * Atomic write entries.json - zapisz do tmp, potem rename
     */
    static async writeEntriesJson(entriesPath, data, output) {
        const maxRetries = 3;
        const retryDelayMs = 500;
        const tmpPath = entriesPath + '.tmp';
        for (let attempt = 0; attempt < maxRetries; attempt++) {
            try {
                // Zapisz do tmp file
                const content = JSON.stringify(data, null, 2);
                fs.writeFileSync(tmpPath, content, 'utf-8');
                // Rename tmp → entries.json (atomic na Windows)
                if (fs.existsSync(entriesPath)) {
                    fs.unlinkSync(entriesPath);
                }
                fs.renameSync(tmpPath, entriesPath);
                if (output && attempt > 0) {
                    output.appendLine(`[Timeline] Successfully wrote entries.json after ${attempt} retries`);
                }
                return true;
            }
            catch (error) {
                const isLastAttempt = attempt === maxRetries - 1;
                // Cleanup tmp file
                try {
                    if (fs.existsSync(tmpPath)) {
                        fs.unlinkSync(tmpPath);
                    }
                }
                catch (e) {
                    // Ignore cleanup errors
                }
                if (!isLastAttempt) {
                    if (output) {
                        output.appendLine(`[Timeline] Failed to write entries.json, retrying (${attempt + 1}/${maxRetries})...`);
                    }
                    await new Promise(resolve => setTimeout(resolve, retryDelayMs));
                    continue;
                }
                // Last attempt failed
                if (output) {
                    output.appendLine(`[Timeline] Failed to write entries.json after ${maxRetries} retries: ${error}`);
                }
                return false;
            }
        }
        return false;
    }
}
exports.EntriesJsonUpdater = EntriesJsonUpdater;
//# sourceMappingURL=entriesJsonUpdater.js.map