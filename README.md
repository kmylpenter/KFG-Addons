# KFG Addons

Modularne dodatki dla Claude Code.

## Szybka Instalacja

```powershell
git clone https://github.com/kmylpenter/KFG-Addons.git
cd KFG-Addons
powershell -ExecutionPolicy Bypass -File install-addons.ps1
```

## Uzycie

```powershell
# Interaktywny wybor dodatkow
.\install-addons.ps1

# Lista dostepnych
.\install-addons.ps1 -List

# Instaluj konkretny
.\install-addons.ps1 -Addon migrateconvo

# Instaluj wszystkie
.\install-addons.ps1 -All
```

## Dostepne Dodatki

| Addon | Opis | Komenda |
|-------|------|---------|
| **claude-history-sync** | Sync historii Claude miedzy urzadzeniami (git) | setup-only |
| **eos** | End of Session - git commit + push | `/eos [summary]` |
| **migrateconvo** | Migracja historii Claude miedzy urzadzeniami | `/migrateconvo` |
| **resume_handoff** | Fix: .md → .yaml w /resume_handoff | `/resume_handoff` |
| **sound-notification** | Dzwiek powiadomienia (Stop + permission_prompt) | auto-hook |
| **windows-console-fix** | Fix: ukrywa okna konsoli Python/UV na Windows | auto-patch |

## Tworzenie Dodatkow

Zobacz [ADDON-DEVELOPMENT.md](ADDON-DEVELOPMENT.md) - instrukcja tworzenia wlasnych dodatkow.

## Struktura

```
KFG-Addons/
├── install-addons.ps1      # Glowny instalator
├── ADDON-DEVELOPMENT.md    # Dokumentacja dla developerow
└── addons/
    └── nazwa-dodatku/
        ├── addon.json      # Metadata
        └── files/          # Pliki do instalacji
```

## Wymagania

- Windows 10/11
- PowerShell 5.0+
- Git

Dodatkowe zaleznosci (Python, Node) instalowane automatycznie wg potrzeb.

## Licencja

MIT
