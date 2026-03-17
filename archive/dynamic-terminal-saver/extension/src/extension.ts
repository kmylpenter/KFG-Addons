// Dynamic Terminal Saver - Entry Point
import * as vscode from 'vscode';
import { saveTerminalState, restoreTerminalState, clearTerminalState, autoRestore, removeTerminalsFromList, addNewTerminal, closeTerminals } from './terminalManager';
import { activateLayoutManager, deactivateLayoutManager } from './layoutManager';

let statusBarItem: vscode.StatusBarItem;

export function activate(context: vscode.ExtensionContext) {
  console.log('Dynamic Terminal Saver aktywowany');

  // Rejestracja komend
  const saveCommand = vscode.commands.registerCommand(
    'dynamicTerminalSaver.saveState',
    saveTerminalState
  );

  const restoreCommand = vscode.commands.registerCommand(
    'dynamicTerminalSaver.restoreState',
    () => restoreTerminalState(false)
  );

  const clearCommand = vscode.commands.registerCommand(
    'dynamicTerminalSaver.clearState',
    clearTerminalState
  );

  const removeCommand = vscode.commands.registerCommand(
    'dynamicTerminalSaver.removeFromList',
    removeTerminalsFromList
  );

  const addCommand = vscode.commands.registerCommand(
    'dynamicTerminalSaver.addTerminal',
    addNewTerminal
  );

  const closeCommand = vscode.commands.registerCommand(
    'dynamicTerminalSaver.closeTerminals',
    closeTerminals
  );

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
  autoRestore(context, 2000);

  // Layout Manager - Layout States
  activateLayoutManager(context);
}

export function deactivate() {
  console.log('Dynamic Terminal Saver dezaktywowany');
  deactivateLayoutManager();
}
