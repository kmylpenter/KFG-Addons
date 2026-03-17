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
exports.ChangeTracker = void 0;
const path = __importStar(require("path"));
class ChangeTracker {
    constructor() {
        this.changes = new Map();
    }
    /**
     * Track changes in a document
     */
    trackChange(document, contentChange) {
        const uri = document.uri.toString();
        // Count characters added/removed
        const range = contentChange.range;
        const rangeLength = contentChange.rangeLength || 0;
        const text = contentChange.text;
        if (!this.changes.has(uri)) {
            this.changes.set(uri, { additions: 0, deletions: 0 });
        }
        const stats = this.changes.get(uri);
        // Count deletions (removed text length)
        stats.deletions += rangeLength;
        // Count additions (inserted text length)
        stats.additions += text.length;
    }
    /**
     * Get change summary for a document and reset tracking
     */
    getSummaryAndReset(document) {
        const uri = document.uri.toString();
        const stats = this.changes.get(uri) || { additions: 0, deletions: 0 };
        const fileName = path.basename(document.uri.fsPath);
        const additions = Math.max(0, stats.additions);
        const deletions = Math.max(0, stats.deletions);
        // Reset tracking for this file
        this.changes.delete(uri);
        // If no changes tracked, return generic label
        if (additions === 0 && deletions === 0) {
            return `${fileName}: Snapshot`;
        }
        return `${fileName}: +${additions}/-${deletions} chars`;
    }
    /**
     * Clear all tracking data
     */
    clear() {
        this.changes.clear();
    }
}
exports.ChangeTracker = ChangeTracker;
//# sourceMappingURL=changeTracker.js.map