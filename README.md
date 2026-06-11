# KFG Addons

Modularne dodatki dla Claude Code. Działa na **Windows** (PowerShell) oraz
**Termux / proot / Linux / macOS** (bash).

## Szybka Instalacja

### Windows (PowerShell)

```powershell
git clone https://github.com/kmylpenter/KFG-Addons.git
cd KFG-Addons
powershell -ExecutionPolicy Bypass -File install-addons.ps1
```

### Termux / proot / Linux / macOS (bash)

```bash
git clone https://github.com/kmylpenter/KFG-Addons.git
cd KFG-Addons
bash install-addons.sh
```

Instalator bash sam wykrywa platformę (`termux` / `proot` / `linux` / `macos`),
honoruje pole `platform` z `addon.json` i **pomija dodatki tylko-Windows**
(z czytelnym komunikatem). Cel instalacji: `~/.claude` (albo `$CLAUDE_TARGET_BASE`).

## Użycie

| Działanie | PowerShell | bash |
|---|---|---|
| Interaktywny wybór | `.\install-addons.ps1` | `bash install-addons.sh` |
| Lista dostępnych | `.\install-addons.ps1 -List` | `bash install-addons.sh --list` |
| Konkretny dodatek | `.\install-addons.ps1 -Addon eos` | `bash install-addons.sh --addon eos` |
| Wszystkie | `.\install-addons.ps1 -All` | `bash install-addons.sh --all` |
| Wymuś nadpisanie | `-All -Force` | `--all --force` |

## Dostępne Dodatki

| Addon | Opis | Platforma |
|-------|------|-----------|
| **autoinit-skills** | Pakiet skilli (petla, session-init, petla-noc, …) + auto-rejestracja | any |
| **ccv3-polish-translation** | Polskie słowa kluczowe dla skill-rules.json | any |
| **ccv3-structure-check** | Auto-tworzenie struktury thoughts/ + ledger | windows |
| **clipboard-workflow-helper** | Rozszerzenie VS Code: Ctrl+C/Ctrl+A+C workflow | windows |
| **czytaj** | Tryb czytania TTS (hands-free, np. w aucie) | termux |
| **eos** | End of Session: handoff + stats + push | any |
| **insights-optimizer** | Optymalizacja na podstawie Insights Report | any |
| **migrateconvo** | Migracja historii Claude między urządzeniami | any |
| **np-v2** | `/np` — nowy projekt CCv3-compatible | any |
| **resume_handoff** | Fix: handoffy .md → .yaml | any |
| **safe-permissions** | Komendy cc/ccd + ochrona YOLO mode | windows |
| **sound-notification** | Dźwięk powiadomienia (Stop / permission) | windows |
| **ssot-dry-audit** | Pure-audit SSOT/DRY → raport | any |
| **statusline-advanced** | Rozbudowana linia statusu (node) | any |
| **terminal-theme** | Motyw KMYLPENTER (Windows Terminal + VS Code) | windows |
| **todo** | Trwała lista TODO między sesjami | any |
| **usage-pace** | Monitor tempa zużycia limitów Max 20x | termux+proot |
| **windows-console-fix** | Ukrywa okna konsoli Python/UV | windows |

> Tabela odzwierciedla pole `platform` z `addon.json`. Dodatki `windows`
> (motyw, dźwięk, VS Code, ochrona cc/ccd) wymagają PowerShella — instalator bash
> je pomija. Aktualną listę zawsze daje `install-addons.{ps1 -List | sh --list}`.

## Tworzenie Dodatków

Zobacz [ADDON-DEVELOPMENT.md](ADDON-DEVELOPMENT.md).

## Struktura

```
KFG-Addons/
├── install-addons.ps1      # Instalator Windows (PowerShell)
├── install-addons.sh       # Instalator Termux/proot/Linux/macOS (bash)
├── ADDON-DEVELOPMENT.md     # Dokumentacja dla developerów
└── addons/
    └── nazwa-dodatku/
        ├── addon.json       # Metadata (name, platform, targets, scripts.postinstall)
        └── files/           # Pliki do instalacji
```

## Wymagania

**Windows:** Windows 10/11 + PowerShell 5.0+ + Git.
**Termux / proot / Linux / macOS:** bash + python3 + Git.

Zależności addonów (Python, Node, termux-api…) instalator **sygnalizuje**;
część dodatków instaluje je sama w swoim `postinstall`.

## Licencja

MIT
