---
name: np
description: Nowy projekt CCv3-compatible z git i thoughts/shared struktura
allowed-tools: Glob, Read, Write, Edit, Bash(git:*), Bash(mkdir:*), Bash(gh:*)
---

# /np - New Project (CCv3)

Tworzy nowy projekt zgodny z CCv3 i git.

## Parametry:
- `$1` - nazwa projektu (wymagane)
- `--with-opc` - sklonuj CCv3 do opc/ (opcjonalne)
- `--github` - utwórz repo na GitHub (opcjonalne)

## Domyślna ścieżka:
`D:\Projekty StriX\` lub zapytaj użytkownika

## Struktura projektu:

```
$1/
├── .claude/
│   └── thoughts/
│       └── shared/
│           ├── handoffs/       # Handoffy YAML między sesjami
│           │   └── .gitkeep
│           ├── plans/          # Plany implementacji
│           │   └── .gitkeep
│           └── research/       # Notatki z researchu
│               └── .gitkeep
├── src/                        # Kod źródłowy (opcjonalnie)
├── CLAUDE.md                   # Instrukcje dla Claude
├── README.md                   # Opis projektu
└── .gitignore
```

## Wykonaj (RÓWNOLEGLE gdzie możliwe):

### Krok 1: Struktura katalogów (jeden Bash)
```bash
cd "D:\Projekty StriX" && mkdir -p "$1/.claude/thoughts/shared/handoffs" "$1/.claude/thoughts/shared/plans" "$1/.claude/thoughts/shared/research" "$1/src" && cd "$1" && git init
```

### Krok 2: Pliki (Write RÓWNOLEGLE)

**CLAUDE.md:**
```markdown
# $1

## Quick Commands
- `/create_handoff [opis]` - zapisz stan przed przerwą
- `/resume_handoff` - wznów pracę z handoffa

## Project Info
- **Created:** [DZIŚ]
- **Type:** [zapytaj lub zostaw puste]
```

**README.md:**
```markdown
# $1

## Description
[Do uzupełnienia]

## Setup
```bash
# Clone
git clone [URL]
cd $1

# If using CCv3
cd opc && uv sync
```

## License
MIT
```

**.gitignore:**
```
# Dependencies
node_modules/
__pycache__/
.venv/
venv/

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Logs
*.log

# CCv3 local
opc/.venv/
```

**.claude/thoughts/shared/handoffs/.gitkeep:**
```
```

**.claude/thoughts/shared/plans/.gitkeep:**
```
```

**.claude/thoughts/shared/research/.gitkeep:**
```
```

### Krok 3: Initial commit
```bash
git add -A && git commit -m "init: projekt $1 z CCv3 structure"
```

### Krok 4: Opcjonalnie CCv3 (jeśli --with-opc)
```bash
git clone https://github.com/anthropics/claude-code.git opc
cd opc && uv sync
```

### Krok 5: Opcjonalnie GitHub (jeśli --github lub zapytaj)
```bash
gh repo create "$1" --private --source=. --push
```

## Output końcowy:
```
✅ Projekt "$1" utworzony

📁 Ścieżka: D:\Projekty StriX\$1
📂 Struktura: .claude/thoughts/shared/ (handoffs, plans, research)
🔧 Git: zainicjalizowany + initial commit

Następne kroki:
1. cd "D:\Projekty StriX\$1"
2. claude
3. Zacznij pracę!
```

## WAŻNE:
- Użyj Write dla WSZYSTKICH plików w JEDNYM RÓWNOLEGŁYM WYWOŁANIU
- Maksymalnie 2-3 wywołania Bash
- Zapytaj o GitHub jeśli nie podano --github
- Data: użyj aktualnej daty
