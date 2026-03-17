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
exports.TitleParser = void 0;
const path = __importStar(require("path"));
class TitleParser {
    /**
     * Parsuj tytuł z komentarza w pierwszych 10-20 liniach dokumentu
     * Szuka wzorca: ==Save: Tytuł== lub @Save: Tytuł (format zależny od rozszerzenia)
     */
    static parseTitle(document) {
        try {
            const ext = path.extname(document.uri.fsPath).toLowerCase();
            const syntax = this.getCommentSyntax(ext);
            const maxLines = 20;
            // Skanuj pierwsze linie w poszukiwaniu keyword pattern
            for (let i = 0; i < Math.min(maxLines, document.lineCount); i++) {
                const line = document.lineAt(i).text;
                const title = this.extractTitle(line, syntax);
                if (title) {
                    return { title, lineNumber: i + 1 };
                }
            }
            return { title: null, lineNumber: null };
        }
        catch (error) {
            return { title: null, lineNumber: null };
        }
    }
    /**
     * Zwróć comment syntax dla danego rozszerzenia pliku
     */
    static getCommentSyntax(ext) {
        const commentMap = {
            '.js': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.ts': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.tsx': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.jsx': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.dart': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.dg': { singleLine: ['//'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.java': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.cs': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.cpp': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.py': { singleLine: ['#'] },
            '.rb': { singleLine: ['#'] },
            '.sh': { singleLine: ['#'] },
            '.bash': { singleLine: ['#'] },
            '.yaml': { singleLine: ['#'] },
            '.yml': { singleLine: ['#'] },
            '.md': { singleLine: ['<!--'], multiLineEnd: '-->' },
            '.html': { singleLine: ['<!--'], multiLineEnd: '-->' },
            '.xml': { singleLine: ['<!--'], multiLineEnd: '-->' },
            '.css': { singleLine: [], multiLineStart: '/*', multiLineEnd: '*/' },
            '.scss': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.less': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.sql': { singleLine: ['--', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.php': { singleLine: ['//', '#', '/*'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.go': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.rs': { singleLine: ['//', '#'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.lua': { singleLine: ['--'], multiLineStart: '/*', multiLineEnd: '*/' },
            '.vim': { singleLine: ['"'], multiLineStart: '/*', multiLineEnd: '*/' }
        };
        return commentMap[ext] || { singleLine: ['//', '#'] };
    }
    /**
     * Ekstrahuj tytuł z linii jeśli zawiera keyword pattern
     * Wspierany format: ==Save: Tytuł== lub @Save: Tytuł
     */
    static extractTitle(line, syntax) {
        // Usuń leading/trailing whitespace
        line = line.trim();
        // Sprawdzaj czy linia zawiera komentarz (single-line)
        for (const commentStart of syntax.singleLine) {
            const idx = line.indexOf(commentStart);
            if (idx !== -1) {
                const afterComment = line.substring(idx + commentStart.length);
                const title = this.extractTitleFromComment(afterComment);
                if (title) {
                    return title;
                }
            }
        }
        // Sprawdzaj czy linia zawiera multi-line komentarz (start)
        if (syntax.multiLineStart && syntax.multiLineEnd) {
            const startIdx = line.indexOf(syntax.multiLineStart);
            if (startIdx !== -1) {
                const endIdx = line.indexOf(syntax.multiLineEnd, startIdx + syntax.multiLineStart.length);
                if (endIdx !== -1) {
                    // Multi-line comment na jednej linii
                    const comment = line.substring(startIdx + syntax.multiLineStart.length, endIdx);
                    const title = this.extractTitleFromComment(comment);
                    if (title) {
                        return title;
                    }
                }
                else {
                    // Multi-line comment start (end na następnej linii)
                    const afterStart = line.substring(startIdx + syntax.multiLineStart.length);
                    const title = this.extractTitleFromComment(afterStart);
                    if (title) {
                        return title;
                    }
                }
            }
        }
        return null;
    }
    /**
     * Ekstrahuj tytuł z tekstu komentarza
     * Szuka wzorca: ==Save: <title>== lub @Save: <title> lub Save: <title>
     */
    static extractTitleFromComment(commentText) {
        // Regex dla formatów: ==Save: Tytuł==, @Save: Tytuł, Save: Tytuł
        // Case-insensitive matching
        const regex = /[=@]?Save:\s*([^=@\n]+?)(?:[=@]|\s*$)/i;
        const match = commentText.match(regex);
        if (match && match[1]) {
            let title = match[1].trim();
            // Usuń trailing white spaces
            title = title.replace(/\s+$/, '');
            // Obetnij do 100 znaków + "..." jeśli dłużej
            const maxLength = 100;
            if (title.length > maxLength) {
                title = title.substring(0, maxLength).trim() + '...';
            }
            // Walidacja - title nie może być pusty
            if (title.length === 0) {
                return null;
            }
            return title;
        }
        return null;
    }
}
exports.TitleParser = TitleParser;
//# sourceMappingURL=titleParser.js.map