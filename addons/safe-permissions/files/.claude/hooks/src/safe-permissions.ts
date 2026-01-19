#!/usr/bin/env node
/**
 * Safe Permissions Hook v3 - YOLO MODE PROTECTION
 *
 * 3-warstwowa ochrona dla --dangerously-skip-permissions:
 *
 * WARSTWA 1: CATASTROPHIC (DENY) - nieodwracalne operacje systemowe
 * WARSTWA 2: CRITICAL PATHS (DENY) - ochrona kluczowych plikow projektowych
 * WARSTWA 3: DELETE COMMANDS (DENY) - rm/rmdir -> trash
 * WARSTWA 4: SUSPICIOUS (ASK) - podejrzane wzorce wymagaja potwierdzenia
 */

interface HookInput {
  session_id: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
}

interface HookOutput {
  decision?: 'allow' | 'deny' | 'ask';
  reason?: string;
}

// ============== WARSTWA 1: CATASTROPHIC COMMANDS ==============
// Komendy ktore moga nieodwracalnie zniszczyc system lub dane

const CATASTROPHIC_PATTERNS: Array<{ pattern: RegExp; description: string }> = [
  // Usuwanie root/home
  { pattern: /\brm\s+(-[rf]+\s+)*[\/~]\s*$/i, description: 'rm na root (/) lub home (~)' },
  { pattern: /\brm\s+(-[rf]+\s+)*\/\s*$/i, description: 'rm na root (/)' },
  { pattern: /\brm\s+-rf\s+\/(?!\w)/i, description: 'rm -rf /' },
  { pattern: /\brm\s+-rf\s+~\/?$/i, description: 'rm -rf ~' },
  { pattern: /\brm\s+-rf\s+[A-Z]:\\$/i, description: 'rm -rf C:\\' },

  // dd - zapis na urzadzenia blokowe
  { pattern: /\bdd\s+.*of=\/dev\//i, description: 'dd zapis na /dev/' },
  { pattern: /\bdd\s+.*of=\\\\\\\\\.\\\\/i, description: 'dd zapis na Windows device' },

  // Formatowanie dyskow
  { pattern: /\bmkfs\./i, description: 'mkfs (formatowanie)' },
  { pattern: /\bformat\s+[A-Z]:/i, description: 'format (Windows)' },
  { pattern: /\bfdisk\b/i, description: 'fdisk (partycjonowanie)' },
  { pattern: /\bparted\b/i, description: 'parted (partycjonowanie)' },

  // Fork bomb
  { pattern: /:\(\)\s*\{\s*:\|:&\s*\}\s*;:/i, description: 'fork bomb' },
  { pattern: /\bfork\s+bomb\b/i, description: 'fork bomb' },

  // Nadpisanie urzadzen
  { pattern: />\s*\/dev\/sd[a-z]/i, description: 'nadpisanie /dev/sd*' },
  { pattern: />\s*\/dev\/nvme/i, description: 'nadpisanie /dev/nvme*' },
  { pattern: /cat\s+.*>\s*\/dev\//i, description: 'cat > /dev/*' },

  // Chmod/chown na root
  { pattern: /\bchmod\s+(-R\s+)?[0-7]{3,4}\s+\/\s*$/i, description: 'chmod na root' },
  { pattern: /\bchown\s+(-R\s+)?.*\s+\/\s*$/i, description: 'chown na root' },

  // Windows system commands
  { pattern: /\bdiskpart\b/i, description: 'diskpart (Windows partycjonowanie)' },
  { pattern: /\bbcdedit\b/i, description: 'bcdedit (Windows boot)' },
  { pattern: /\bsfc\s+\/scannow/i, description: 'sfc (Windows system files)' },
];

// ============== WARSTWA 2: CRITICAL PATHS ==============
// Sciezki projektowe ktore nigdy nie powinny byc usuwane

const CRITICAL_PATHS = [
  // Version control
  '.git',
  '.svn',
  '.hg',

  // Package managers
  'node_modules',
  '.pnpm',
  'vendor',
  '__pycache__',
  '.venv',
  'venv',

  // Claude/IDE config
  '.claude',
  '.vscode',
  '.idea',

  // Manifests (usuwanie = zniszczenie projektu)
  'package.json',
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'Cargo.toml',
  'Cargo.lock',
  'go.mod',
  'go.sum',
  'requirements.txt',
  'pyproject.toml',
  'Gemfile',
  'Gemfile.lock',
  'composer.json',
  'composer.lock',

  // Environment & secrets
  '.env',
  '.env.local',
  '.env.production',
  '.envrc',
];

// ============== WARSTWA 3: DELETE COMMANDS ==============
// Komendy usuwajace -> przekierowanie na trash

const DELETE_PATTERNS = [
  { pattern: /\brm\s/, cmd: 'rm' },
  { pattern: /\brmdir\s/, cmd: 'rmdir' },
  { pattern: /\bdel\s/, cmd: 'del' },
  { pattern: /\bremove-item\s/i, cmd: 'Remove-Item' },
  { pattern: /\brm$/, cmd: 'rm' },  // rm na koncu
  { pattern: /\$\([^)]*\brm\b/, cmd: 'rm (subshell)' },
  { pattern: /`[^`]*\brm\b/, cmd: 'rm (backticks)' },
];

// ============== WARSTWA 4: SUSPICIOUS PATTERNS ==============
// Podejrzane wzorce - wymagaja potwierdzenia ale nie blokuja

const SUSPICIOUS_PATTERNS: Array<{ pattern: RegExp; description: string }> = [
  { pattern: /\bfind\s+.*-delete\b/i, description: 'find -delete (masowe usuwanie)' },
  { pattern: /\bxargs\s+.*rm\b/i, description: 'xargs rm (masowe usuwanie)' },
  { pattern: /\brm\s+.*\*\*/i, description: 'rm z ** (rekurencyjny wildcard)' },
  { pattern: /\brm\s+-rf\s+\.\*/i, description: 'rm -rf .* (ukryte pliki)' },
  { pattern: /&&\s*rm\s+/i, description: 'chained rm command' },
  { pattern: /;\s*rm\s+/i, description: 'chained rm command' },
  { pattern: /\|\s*xargs\s+rm/i, description: 'piped to xargs rm' },
  { pattern: /\bgit\s+clean\s+-[fd]+x/i, description: 'git clean -fdx (usuwa ignored files)' },
  { pattern: /\bgit\s+reset\s+--hard/i, description: 'git reset --hard (usuwa zmiany)' },
  { pattern: /\bgit\s+push\s+.*--force/i, description: 'git push --force (nadpisuje historie)' },
  { pattern: /\bgit\s+push\s+-f\b/i, description: 'git push -f (nadpisuje historie)' },
];

// ============== LOGIKA HOOKA ==============

function checkCatastrophic(command: string): { blocked: boolean; description: string } {
  for (const { pattern, description } of CATASTROPHIC_PATTERNS) {
    if (pattern.test(command)) {
      return { blocked: true, description };
    }
  }
  return { blocked: false, description: '' };
}

function checkCriticalPaths(command: string): { blocked: boolean; path: string } {
  const normalized = command.toLowerCase();

  // Czy to komenda usuwajaca?
  const isDeleteCommand = DELETE_PATTERNS.some(({ pattern }) => pattern.test(normalized));
  if (!isDeleteCommand) {
    return { blocked: false, path: '' };
  }

  // Sprawdz czy celuje w krytyczna sciezke
  for (const criticalPath of CRITICAL_PATHS) {
    // Escape special regex characters
    const escaped = criticalPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

    // Pattern dla sciezek z kropka (np. .git, .env) i bez kropki (np. node_modules)
    const patterns = [
      new RegExp(`(?:^|\\s|/|\\\\)${escaped}(?:\\s|$|/|\\\\|")`, 'i'),  // jako segment sciezki
      new RegExp(`\\s${escaped}$`, 'i'),  // na koncu komendy
      new RegExp(`^${escaped}\\s`, 'i'),  // na poczatku komendy
      new RegExp(`^${escaped}$`, 'i'),    // sama sciezka
    ];

    for (const p of patterns) {
      if (p.test(command)) {
        return { blocked: true, path: criticalPath };
      }
    }
  }

  return { blocked: false, path: '' };
}

function checkDeleteCommands(command: string): { found: boolean; cmd: string } {
  const normalized = command.toLowerCase();

  for (const { pattern, cmd } of DELETE_PATTERNS) {
    if (pattern.test(normalized)) {
      return { found: true, cmd };
    }
  }

  return { found: false, cmd: '' };
}

function checkSuspicious(command: string): { suspicious: boolean; description: string } {
  for (const { pattern, description } of SUSPICIOUS_PATTERNS) {
    if (pattern.test(command)) {
      return { suspicious: true, description };
    }
  }
  return { suspicious: false, description: '' };
}

function extractTarget(command: string): string {
  // Probuj wyciagnac cel komendy rm/del
  const match = command.match(/\b(?:rm|rmdir|del|remove-item)\s+(?:-[rf]+\s+)*(.+)$/i);
  if (match) {
    return match[1].trim();
  }
  return '<cel>';
}

function processHook(input: HookInput): HookOutput {
  const { tool_name, tool_input } = input;

  // Tylko dla Bash
  if (tool_name !== 'Bash') {
    return {};  // Nie ingeruj - settings.json obsluzy
  }

  const command = (tool_input.command as string) || '';

  // WARSTWA 1: Catastrophic - natychmiastowy DENY
  const catastrophic = checkCatastrophic(command);
  if (catastrophic.blocked) {
    return {
      decision: 'deny',
      reason: `🚫 CATASTROPHIC COMMAND BLOCKED\n\n` +
              `Wykryto: ${catastrophic.description}\n\n` +
              `Ta komenda moze spowodowac NIEODWRACALNE uszkodzenie systemu lub utrate danych.\n` +
              `Nie mozna jej wykonac nawet w trybie --dangerously-skip-permissions.`
    };
  }

  // WARSTWA 2: Critical Paths - DENY z wyjasnieniem
  const critical = checkCriticalPaths(command);
  if (critical.blocked) {
    return {
      decision: 'deny',
      reason: `🛡️ CRITICAL PATH PROTECTED\n\n` +
              `Zablokowano usuwanie: ${critical.path}\n\n` +
              `Ta sciezka jest krytyczna dla projektu.\n` +
              `Jezeli naprawde musisz ja usunac, zrob to recznie poza Claude Code.`
    };
  }

  // WARSTWA 3: Delete Commands - DENY -> suggest trash
  const deleteCheck = checkDeleteCommands(command);
  if (deleteCheck.found) {
    const target = extractTarget(command);
    return {
      decision: 'deny',
      reason: `♻️ Uzyj 'trash' zamiast '${deleteCheck.cmd}'\n\n` +
              `Trash przenosi do Kosza zamiast trwale usuwac.\n\n` +
              `Zamiast tego uruchom:\n  trash ${target}`
    };
  }

  // WARSTWA 4: Suspicious - ASK (wymaga potwierdzenia)
  const suspicious = checkSuspicious(command);
  if (suspicious.suspicious) {
    return {
      decision: 'ask',
      reason: `⚠️ Podejrzany wzorzec: ${suspicious.description}\n\n` +
              `Ta komenda moze miec nieprzewidziane skutki.\n` +
              `Czy na pewno chcesz ja wykonac?`
    };
  }

  // Wszystko OK - pozwol settings.json zdecydowac
  return {};
}

// Cross-platform stdin reading
async function main() {
  const chunks: string[] = [];

  process.stdin.setEncoding('utf-8');

  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  try {
    const input = JSON.parse(chunks.join('')) as HookInput;
    const output = processHook(input);
    console.log(JSON.stringify(output));
  } catch {
    // Parse error - nie blokuj
    console.log(JSON.stringify({}));
  }
}

main();
