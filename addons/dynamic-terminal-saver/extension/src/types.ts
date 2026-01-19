// Interfejsy dla Dynamic Terminal Saver

export interface SavedTerminal {
  name: string;
  cwd: string;
  splitIndex: number;
  color?: string;  // np. 'terminal.ansiRed'
  icon?: string;   // np. 'rocket', 'folder', 'terminal-bash'
}

export interface TerminalState {
  version: string;
  savedAt: string;
  terminals: SavedTerminal[];
}
