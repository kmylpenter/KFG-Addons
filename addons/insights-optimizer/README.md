# Insights Optimizer

Optymalizacja Claude Code na podstawie analizy **Claude Code Insights Report** (836 msg, 59 sesji, 21 dni).

## Co rozwiazuje

| Problem | Liczba | Rozwiazanie |
|---------|--------|-------------|
| Wrong Approach | 30 | CLAUDE.md: architecture confirmation + environment constraints |
| Buggy Code | 26 | Rule: verify-before-done + Hook: gas-html-syntax-check |
| Misunderstood Request | 16 | CLAUDE.md: audit vs fix mode distinction |
| Excessive Changes | 9 | Rule: minimal-change-principle |
| File Too Large | 13 | Hook: large-file-read-guard |
| Permission Prompts | ~60% | settings-insights.json: pre-approved safe operations |

## Zawartosc

### 1. Globalny CLAUDE.md (42 linie)

Ladowany w KAZDEJ sesji. Pokrywa:
- **Environment** - Termux Android, /tmp restricted, tablet kiosk target
- **Architecture Confirmation** - 1-linijkowy checkpoint przed implementacja
- **Verification Gate** - wymaga re-read + smoke-check przed "done"
- **Audit vs Fix Mode** - zero edycji w trybie audytu
- **Session Discipline** - ostrzezenie przy 4+ niezwiazanych taskach
- **Large File Edits** - chirurgiczne edycje z offset/limit
- **Zoho CRM Fields** - grep-first rule

### 2. Reguly (3 pliki)

| Regula | Adresuje |
|--------|----------|
| `verify-before-done.md` | 26 buggy-code events - checklista weryfikacji, bug patterns, "5th Time Rule" |
| `minimal-change-principle.md` | 9 excessive-changes - decision ladder, scope lock, file count check |
| `follow-existing-plan.md` | 30 wrong-approach - 3-file rule, anti-exploration loop |

### 3. Hooki (2 bash scripts)

| Hook | Event | Co robi |
|------|-------|---------|
| `gas-html-syntax-check.sh` | PostToolUse (Edit\|Write) | Walidacja .gs/.js (node --check) i .html (python html.parser) |
| `large-file-read-guard.sh` | PreToolUse (Read) | Ostrzezenie gdy plik >2000 linii bez offset/limit |

### 4. Uprawnienia i konfiguracja

`settings-insights.json` zawiera:
- **permissions** - 35 pre-approved safe operations (git read, node, unix tools)
- **hooks_to_add** - konfiguracja hookow do settings.json
- **env_to_add** - 3 nowe zmienne srodowiskowe

## Instalacja

### Krok 1: Zainstaluj addon

```powershell
.\install-addons.ps1 -Addon insights-optimizer
```

Kopiuje: CLAUDE.md, rules, hook scripts.

### Krok 2: Uprawnienia (settings.local.json)

Scal `permissions` z `settings-insights.json` do `~/.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git log:*)", "Bash(git diff:*)", "Bash(git status:*)",
      "Bash(node:*)", "Bash(npm:*)", "Bash(npx:*)",
      "Bash(cat:*)", "Bash(ls:*)", "Bash(wc:*)", "Bash(mkdir:*)",
      "Bash(jq:*)", "Bash(tldr:*)", "Bash(python3:*)", "Bash(uv:*)"
    ]
  }
}
```

### Krok 3: Hooki (settings.json)

Dodaj do sekcji `PostToolUse`:
```json
{
  "matcher": "Edit|Write",
  "hooks": [{
    "type": "command",
    "command": "bash $HOME/.claude/hooks/src/gas-html-syntax-check.sh",
    "timeout": 10
  }]
}
```

Dodaj do sekcji `PreToolUse`:
```json
{
  "matcher": "Read",
  "hooks": [{
    "type": "command",
    "command": "bash $HOME/.claude/hooks/src/large-file-read-guard.sh",
    "timeout": 3
  }]
}
```

### Krok 4: Env vars (settings.json)

Dodaj do `env`:
```json
"CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000",
"CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
"CLAUDE_CODE_GLOB_TIMEOUT_SECONDS": "30"
```

### Krok 5: chmod

```bash
chmod +x ~/.claude/hooks/src/gas-html-syntax-check.sh
chmod +x ~/.claude/hooks/src/large-file-read-guard.sh
```

## Oczekiwany efekt

| Metryka | Przed | Po |
|---------|-------|----|
| Friction events / sesja | ~1.5 | ~0.5 (-66%) |
| Permission prompts | czeste | rzadkie (-60-70%) |
| File Too Large errors | 13 | ~0 (-100%) |
| Premature "done" claims | ~26 | ~8 (-70%) |
| Wrong architecture pivots | ~30 | ~10 (-66%) |
| GAS/HTML syntax errors shipped | nieznana | ~0 |

## Kompatybilnosc

- Termux Android: TAK (natywne bash/node/python3)
- Windows: TAK (bash przez Git Bash, node, python)
- macOS/Linux: TAK
- Wymaga: `node >= 18`, `python3 >= 3.8`, `jq`
