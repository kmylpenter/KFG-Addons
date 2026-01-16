# Safe Permissions Addon v2

Bezpieczne uprawnienia dla Claude Code z **podejściem warstwowym**.

## Architektura

```
┌─────────────────────────────────────────────────────┐
│  Claude chce wykonać: cd tmp && rm -rf folder/      │
└─────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│  WARSTWA 1: settings.json                           │
│  ├── deny: Bash(rm:*) → BLOK jeśli zaczyna od rm    │
│  └── NIE łapie: "cd tmp && rm" (zaczyna od cd)      │
└─────────────────────────────────────────────────────┘
                         │ (przepuszcza)
                         ▼
┌─────────────────────────────────────────────────────┐
│  WARSTWA 2: hook PreToolUse                         │
│  ├── Skanuje CAŁĄ komendę                           │
│  ├── Znajduje "rm" gdziekolwiek                     │
│  └── DENY + sugestia: "Użyj trash folder/"          │
└─────────────────────────────────────────────────────┘
```

## Co blokuje

| Komenda | Warstwa 1 | Warstwa 2 | Wynik |
|---------|-----------|-----------|-------|
| `rm file.txt` | ✅ BLOK | - | DENY |
| `cd tmp && rm file` | ❌ | ✅ BLOK | DENY |
| `find . \| xargs rm` | ❌ | ✅ BLOK | DENY |
| `$(rm file)` | ❌ | ✅ BLOK | DENY |
| `trash file.txt` | ALLOW | - | OK |

## Co pozwala (bez promptów)

- `trash` - bezpieczne usuwanie do Kosza
- `git`, `gh` - operacje git (bez --force)
- `npm`, `node`, `npx`, `bun` - JavaScript
- `python`, `pip`, `uv`, `pytest` - Python
- `ls`, `mkdir`, `cp`, `mv`, `cat`, `grep` - podstawowe
- `docker`, `docker-compose` - kontenery

## Co wymaga potwierdzenia

- `git push` - push do remote
- `curl`, `wget` - pobieranie z sieci

## Co blokuje (pliki)

- `.env`, `.env.*` - zmienne środowiskowe
- `secrets/`, `credentials/` - sekrety
- `*.pem`, `*.key`, `id_rsa`, `id_ed25519` - klucze
- `~/.ssh/**` - zapis do SSH

## Instalacja

```powershell
# Via KFG installer
cd "D:\Projekty DELL KG\KFG-Addons"
.\install.ps1 safe-permissions
```

## Wymagania

- Node.js 18+
- npm (dla trash-cli i esbuild)

## Pliki

```
~/.claude/
├── settings.json              # + permissions allow/deny/ask
├── settings-permissions.json  # fragment do merge
└── hooks/
    ├── src/safe-permissions.ts
    └── dist/safe-permissions.mjs
```

## Użycie

```bash
# Zamiast rm
trash plik.txt
trash -rf folder/

# Działa jak rm ale przenosi do Kosza
trash *.tmp
```
