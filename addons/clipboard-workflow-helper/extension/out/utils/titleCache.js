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
exports.TitleCache = void 0;
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
/**
 * Cache tytułów dla entries bez source field
 * Umożliwia "recovery" jeśli VSCode się zamknie zanim extension update entries.json
 *
 * WAŻNE: Używamy VSCode globalStoragePath zamiast extensionPath!
 * Powód: extensionPath może być symlinkowany na Zoho WorkDrive (problemy z lockingiem)
 * globalStoragePath jest zawsze w AppData (bezpieczny, nie symlinkowany)
 */
class TitleCache {
    static initialize(globalStoragePath) {
        // ZMIANA: używaj globalStoragePath zamiast extensionPath
        // Gwarantuje że cache będzie w AppData, nie na WorkDrive
        this.cachePath = path.join(globalStoragePath, 'title-cache.json');
        this.loadCache();
    }
    /**
     * Zapisz tytuł dla danego resource (pliku)
     * Użyj gdy extension parsuje title przed update entries.json
     */
    static saveTitle(resourceUri, title, backupId) {
        try {
            this.cache[resourceUri] = {
                title,
                backupId,
                timestamp: Date.now()
            };
            this.persistCache();
        }
        catch (error) {
            // Ignore cache errors
        }
    }
    /**
     * Pobierz cached title dla danego resource
     */
    static getTitle(resourceUri) {
        return this.cache[resourceUri] || null;
    }
    /**
     * Wyczyść cached title dla danego resource (po successful update)
     */
    static clearTitle(resourceUri) {
        delete this.cache[resourceUri];
        this.persistCache();
    }
    /**
     * Wyczyść stare cache entries (starsze niż 7 dni)
     */
    static cleanOldEntries() {
        const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
        const now = Date.now();
        let hasChanges = false;
        for (const resourceUri in this.cache) {
            if (now - this.cache[resourceUri].timestamp > sevenDaysMs) {
                delete this.cache[resourceUri];
                hasChanges = true;
            }
        }
        if (hasChanges) {
            this.persistCache();
        }
    }
    static loadCache() {
        try {
            if (fs.existsSync(this.cachePath)) {
                const content = fs.readFileSync(this.cachePath, 'utf-8');
                this.cache = JSON.parse(content);
            }
            else {
                this.cache = {};
            }
        }
        catch (error) {
            this.cache = {};
        }
    }
    static persistCache() {
        try {
            const content = JSON.stringify(this.cache, null, 2);
            fs.writeFileSync(this.cachePath, content, 'utf-8');
        }
        catch (error) {
            // Ignore write errors
        }
    }
}
exports.TitleCache = TitleCache;
TitleCache.cachePath = '';
TitleCache.cache = {};
//# sourceMappingURL=titleCache.js.map