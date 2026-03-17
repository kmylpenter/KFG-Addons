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
exports.activate = activate;
exports.deactivate = deactivate;
// Dynamic Terminal Saver - Entry Point
const vscode = __importStar(require("vscode"));
const terminalManager_1 = require("./terminalManager");
const layoutManager_1 = require("./layoutManager");
let statusBarItem;
function activate(context) {
    console.log('Dynamic Terminal Saver aktywowany');
    // Rejestracja komend
    const saveCommand = vscode.commands.registerCommand('dynamicTerminalSaver.saveState', terminalManager_1.saveTerminalState);
    const restoreCommand = vscode.commands.registerCommand('dynamicTerminalSaver.restoreState', () => (0, terminalManager_1.restoreTerminalState)(false));
    const clearCommand = vscode.commands.registerCommand('dynamicTerminalSaver.clearState', terminalManager_1.clearTerminalState);
    const removeCommand = vscode.commands.registerCommand('dynamicTerminalSaver.removeFromList', terminalManager_1.removeTerminalsFromList);
    const addCommand = vscode.commands.registerCommand('dynamicTerminalSaver.addTerminal', terminalManager_1.addNewTerminal);
    const closeCommand = vscode.commands.registerCommand('dynamicTerminalSaver.closeTerminals', terminalManager_1.closeTerminals);
    context.subscriptions.push(saveCommand, restoreCommand, clearCommand, removeCommand, addCommand, closeCommand);
    // Status Bar Buttons
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'dynamicTerminalSaver.saveState';
    statusBarItem.text = '$(save) Terminals';
    statusBarItem.tooltip = 'Zapisz stan terminali';
    statusBarItem.show();
    const addBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 99);
    addBarItem.command = 'dynamicTerminalSaver.addTerminal';
    addBarItem.text = '$(add)';
    addBarItem.tooltip = 'Dodaj nowy terminal z kolorem';
    addBarItem.show();
    const closeBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 98);
    closeBarItem.command = 'dynamicTerminalSaver.closeTerminals';
    closeBarItem.text = '$(close)';
    closeBarItem.tooltip = 'Zamknij terminale';
    closeBarItem.show();
    const removeBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 97);
    removeBarItem.command = 'dynamicTerminalSaver.removeFromList';
    removeBarItem.text = '$(trash)';
    removeBarItem.tooltip = 'Usun z listy zapisanych';
    removeBarItem.show();
    context.subscriptions.push(statusBarItem, addBarItem, closeBarItem, removeBarItem);
    // Auto-restore przy starcie (2s delay, Claude Code juz aktywne przez extensionDependencies)
    (0, terminalManager_1.autoRestore)(context, 2000);
    // Layout Manager - Layout States
    (0, layoutManager_1.activateLayoutManager)(context);
}
function deactivate() {
    console.log('Dynamic Terminal Saver dezaktywowany');
    (0, layoutManager_1.deactivateLayoutManager)();
}
//# sourceMappingURL=extension.js.map