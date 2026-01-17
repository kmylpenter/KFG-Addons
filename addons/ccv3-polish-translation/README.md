# CCv3 Polish Translation

Polskie słowa kluczowe dla systemu skill-rules.json w Claude Code.

## Statystyki

| Kategoria | Ilość |
|-----------|-------|
| Skills przetłumaczonych | 70 |
| Agents przetłumaczonych | 6 |
| Łącznie polskich słów kluczowych | 853 |
| Testy przechodzące | 31/31 |
| Promptów przeanalizowanych | 5,934 |

## Co zawiera v3

1. **Curated keywords** - ręcznie dobrane słowa z polskimi znakami
2. **ASCII warianty** - wersje bez polskich znaków (sprawdz = sprawdź)
3. **Odkryte keywords** - z analizy 5934 Twoich promptów

## Instalacja

```bash
# Z katalogu KFG-Addons
cd addons/ccv3-polish-translation
python apply-translations-v2.py
```

Lub ręcznie skopiuj:
```bash
copy files\skills\skill-rules.json %USERPROFILE%\.claude\skills\skill-rules.json
```

## Rollback

### Metoda 1: Przywróć backup
```powershell
Copy-Item "$env:USERPROFILE\.claude\skills\skill-rules.json.backup-2026-01-17" "$env:USERPROFILE\.claude\skills\skill-rules.json"
```

### Metoda 2: Git reset (jeśli commited)
```bash
cd ~/.claude/skills
git checkout HEAD -- skill-rules.json
```

### Metoda 3: Reinstaluj CCv3
```bash
# Pobierz świeży skill-rules.json z CCv3
```

## Testowanie

```bash
python test-polish-prompts.py
```

## Przykłady polskich promptów

| Polski prompt | Wyzwala skill |
|--------------|---------------|
| "napraw tego buga" | fix |
| "zbuduj nową funkcjonalność" | build |
| "eksploruj bazę kodu" | explore |
| "debuguj problem" | debug |
| "stwórz handoff" | create_handoff |
| "commituj zmiany" | commit |
| "przejrzyj mój kod" | review |
| "sprawdź bezpieczeństwo" | security |
| "uruchom testy" | test |
| "refaktoruj ten moduł" | refactor |

## Pliki

| Plik | Opis |
|------|------|
| `addon.json` | Metadata addona |
| `polish-keywords-v2.json` | Curated słowa kluczowe po polsku |
| `apply-translations-v2.py` | Skrypt aplikujący tłumaczenia |
| `test-polish-prompts.py` | Testy polskich promptów |
| `files/skills/skill-rules.json` | Gotowy przetłumaczony plik |

## Uwagi

- Addon nadpisuje `~/.claude/skills/skill-rules.json`
- Backup zapisany jako `skill-rules.json.backup-2026-01-17`
- Po aktualizacji CCv3 może być potrzebne ponowne uruchomienie skryptu
