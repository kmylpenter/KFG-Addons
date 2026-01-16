#!/usr/bin/env node
/**
 * Safe Permissions Hook v2 - SIMPLIFIED
 *
 * Robi TYLKO jedno: blokuje rm/rmdir/del i sugeruje trash.
 * Cała reszta logiki jest w settings.json.
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

// Wykryj komendę usuwającą w dowolnym miejscu stringa
function containsDeleteCommand(command: string): { found: boolean; cmd: string; suggestion: string } {
  const normalized = command.toLowerCase();

  // Patterns do wykrycia (uwzględnia pipe, subshell, &&, ;, ||, &)
  const deletePatterns = [
    { pattern: /\brm\s/, cmd: 'rm', suggestion: 'trash' },
    { pattern: /\brmdir\s/, cmd: 'rmdir', suggestion: 'trash' },
    { pattern: /\bdel\s/, cmd: 'del', suggestion: 'trash' },
    { pattern: /\bremove-item\s/i, cmd: 'Remove-Item', suggestion: 'trash' },
    { pattern: /\brm$/, cmd: 'rm', suggestion: 'trash' },  // rm na końcu
  ];

  for (const { pattern, cmd, suggestion } of deletePatterns) {
    if (pattern.test(normalized)) {
      return { found: true, cmd, suggestion };
    }
  }

  // Sprawdź też subshells i backticks
  if (/\$\([^)]*\brm\b/.test(normalized) || /`[^`]*\brm\b/.test(normalized)) {
    return { found: true, cmd: 'rm (w subshell)', suggestion: 'trash' };
  }

  return { found: false, cmd: '', suggestion: '' };
}

// Sprawdź czy to NAPRAWDĘ niebezpieczne (rm -rf / lub ~)
function isDangerousDelete(command: string): boolean {
  const patterns = [
    /rm\s+(-[rf]+\s+)*[\/~]\s*$/i,      // rm -rf / lub rm -rf ~
    /rm\s+(-[rf]+\s+)*\/\s*$/i,          // rm /
    /rm\s+-rf\s+\//i,                     // rm -rf /cokolwiek na root
    /rmdir\s+[\/~]\s*$/i,                 // rmdir /
  ];

  return patterns.some(p => p.test(command));
}

function processHook(input: HookInput): HookOutput {
  const { tool_name, tool_input } = input;

  // Tylko dla Bash
  if (tool_name !== 'Bash') {
    return {};  // Nie ingeruj - settings.json obsłuży
  }

  const command = (tool_input.command as string) || '';

  // Sprawdź czy zawiera komendę usuwającą
  const deleteCheck = containsDeleteCommand(command);

  if (deleteCheck.found) {
    // Czy to BARDZO niebezpieczne?
    if (isDangerousDelete(command)) {
      return {
        decision: 'deny',
        reason: `ZABLOKOWANO: Niebezpieczna komenda usuwania. Nigdy nie usuwaj root (/) lub home (~).`
      };
    }

    // Zwykłe rm - zablokuj i zasugeruj trash
    return {
      decision: 'deny',
      reason: `Uzyj 'trash' zamiast '${deleteCheck.cmd}'. Trash przenosi do Kosza zamiast trwale usuwac.\n\nPrzyklad: trash ${command.replace(/^(rm|rmdir|del)\s*/i, '')}`
    };
  }

  // Nie rm/rmdir/del - pozwól settings.json zdecydować
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
