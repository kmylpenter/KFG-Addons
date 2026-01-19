# Safe Permissions Addon v3.2

**YOLO Mode Protection** + komendy `cc`/`ccd` dla Claude Code.

## Problem

Flaga `--dangerously-skip-permissions` wylacza wszystkie prompty o potwierdzenie. Claude moze:
- Usunac krytyczne pliki projektu
- Wykonac destrukcyjne komendy systemowe
- Nadpisac historie git

Ten addon dodaje **4-warstwowa ochrone** ktora dziala NAWET w YOLO mode.

## Architektura

```
┌─────────────────────────────────────────────────────────────┐
│  Claude chce wykonac: cd tmp && rm -rf .git                  │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  WARSTWA 1: settings.json (pattern matching)                 │
│  ├── deny: Bash(rm:*) → NIE lapie (zaczyna od "cd")          │
│  └── przepuszcza dalej...                                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  WARSTWA 2: CATASTROPHIC (hook)                              │
│  ├── Czy to rm -rf / lub dd of=/dev/sda?                     │
│  └── NIE → przepusc dalej                                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  WARSTWA 3: CRITICAL PATHS (hook)                            │
│  ├── Czy usuwa .git, node_modules, package.json?             │
│  └── TAK → DENY "Zablokowano usuwanie: .git"                 │
└─────────────────────────────────────────────────────────────┘
```

## Warstwy ochrony

### Warstwa 1: CATASTROPHIC (DENY)

Nieodwracalne operacje systemowe - **zawsze blokowane**:

| Komenda | Opis |
|---------|------|
| `rm -rf /` | Usuniecie root |
| `rm -rf ~` | Usuniecie home |
| `dd if=... of=/dev/sda` | Nadpisanie dysku |
| `mkfs.ext4 /dev/sda1` | Formatowanie |
| `fdisk`, `parted`, `diskpart` | Partycjonowanie |
| `:(){ :\|:& };:` | Fork bomb |

### Warstwa 2: CRITICAL PATHS (DENY)

Ochrona kluczowych plikow projektu:

| Kategoria | Chronione |
|-----------|-----------|
| VCS | `.git`, `.svn`, `.hg` |
| Packages | `node_modules`, `vendor`, `.venv`, `__pycache__` |
| IDE | `.claude`, `.vscode`, `.idea` |
| Manifests | `package.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, `pyproject.toml` |
| Secrets | `.env`, `.env.local`, `.envrc` |

### Warstwa 3: DELETE COMMANDS (DENY → trash)

Wszystkie komendy usuwajace przekierowane na `trash`:

```
rm file.txt      → "Uzyj: trash file.txt"
cd tmp && rm -f  → "Uzyj: trash ..."
$(rm hidden)     → wykryty subshell
```

### Warstwa 4: SUSPICIOUS (ASK)

Podejrzane wzorce wymagaja potwierdzenia:

| Pattern | Opis |
|---------|------|
| `find -delete` | Masowe usuwanie |
| `xargs rm` | Piped delete |
| `rm **/*.js` | Recursive wildcard |
| `git push --force` | Nadpisanie historii |
| `git reset --hard` | Utrata zmian |
| `git clean -fdx` | Usuniecie ignored |

## Instalacja

```powershell
cd "D:\Projekty DELL KG\KFG-Addons"
.\install-addons.ps1 -Addon safe-permissions
```

Po instalacji otworz nowy terminal.

## Uzycie

```powershell
cc       # Claude + git sync (history pull/push, project pull)
ccd      # YOLO mode + git sync (--dangerously-skip-permissions)
cc-fast  # cc bez git sync (-SkipGit -SkipSync)
claude   # Surowy Claude (bez git sync)
```

### Przepływ cc/ccd

```
1. History sync    → git pull ~/.claude-history
2. Project pull    → pyta "Pull latest? [Y/n]"
3. Claude          → uruchamia claude (lub --dangerously-skip-permissions)
4. History push    → git push ~/.claude-history
```

### Porownanie

| Komenda | Git sync | YOLO mode | Hook ochrony |
|---------|----------|-----------|--------------|
| `cc` | Tak | Nie | Tak |
| `ccd` | Tak | **Tak** | Tak |
| `cc-fast` | Nie | Nie | Tak |
| `claude` | Nie | Nie | Tak |

## Wymagania

- Node.js 18+
- npm (dla trash-cli i esbuild)

## Pliki instalowane

```
~/.claude/
├── settings.json              # + permissions + hook
├── settings-permissions.json  # fragment do merge
├── scripts/
│   └── install-safe-permissions.ps1
└── hooks/
    ├── src/safe-permissions.ts
    └── dist/safe-permissions.mjs
```

## Testowanie

```bash
# Powinno byc zablokowane (CATASTROPHIC)
rm -rf /

# Powinno byc zablokowane (CRITICAL)
rm -rf .git
rm node_modules

# Powinno przekierowac na trash
rm file.txt
# → "Uzyj: trash file.txt"

# Powinno pytac (SUSPICIOUS)
git push --force origin main
# → "Podejrzany wzorzec: git push --force"
```

## Uzycie trash

```bash
# Zamiast rm
trash plik.txt
trash -rf folder/
trash *.tmp

# Dziala jak rm ale przenosi do Kosza
# Mozna odzyskac!
```

## Zrodla

Inspirowane:
- [dangerous-command-blocker](https://github.com/davila7/claude-code-templates/tree/main/cli-tool/components/hooks/security)
- [Lasso Security Defender](https://www.lasso.security/blog/the-hidden-backdoor-in-claude-coding-assistant)
