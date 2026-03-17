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
exports.copyAndCreateTimeline = copyAndCreateTimeline;
const vscode = __importStar(require("vscode"));
const timelineManager_1 = require("../utils/timelineManager");
const autoBackupManager_1 = require("../utils/autoBackupManager");
async function copyAndCreateTimeline(changeTracker) {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        return;
    }
    // Only process real files, not output channels or untitled docs
    if (editor.document.uri.scheme !== 'file') {
        vscode.window.showWarningMessage(`Cannot create timeline for ${editor.document.uri.scheme} documents. Open a real file.`);
        return;
    }
    try {
        // Select all
        await vscode.commands.executeCommand('editor.action.selectAll');
        // Get all text
        const text = editor.document.getText();
        // Copy to clipboard
        await vscode.env.clipboard.writeText(text);
        // Generate label from change tracker (shows what changed)
        const label = changeTracker.getSummaryAndReset(editor.document);
        // Save document first
        if (editor.document.isDirty) {
            await editor.document.save();
        }
        // Create Timeline entry with auto-generated label from changes
        const success = await timelineManager_1.TimelineManager.addTimelineEntry(editor.document, label);
        // Show confirmation message with change summary
        if (success) {
            // Reset auto-backup timer - zapobiega duplikatom (30s bez auto-backup)
            autoBackupManager_1.AutoBackupManager.resetTimer(editor.document.uri.toString());
            // Success: Show in status bar (auto-hides after 5s)
            vscode.window.setStatusBarMessage(`✓ Copied to clipboard and saved. Timeline: ${label}`, 5000);
        }
        else {
            // Error: Show notification with action buttons
            vscode.window.showWarningMessage(`Timeline entry failed`, 'View Config', 'View Logs').then(choice => {
                if (choice === 'View Config') {
                    const configPath = vscode.Uri.file(require('path').join(require('vscode').extensions.getExtension('local.clipboard-workflow-helper')?.extensionPath || '', 'timeline-config.json'));
                    vscode.commands.executeCommand('vscode.open', configPath);
                }
                else if (choice === 'View Logs') {
                    vscode.commands.executeCommand('workbench.action.output.toggleOutput');
                }
            });
        }
        // Clear selection
        const pos = editor.selection.active;
        editor.selection = new vscode.Selection(pos, pos);
    }
    catch (error) {
        vscode.window.showErrorMessage(`Failed: ${error}`);
    }
}
//# sourceMappingURL=copyAndCreateTimeline.js.map