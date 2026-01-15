---
name: eos
description: End of Session - handoff + eksport stats + git commit + push. Triggers: eos, koniec sesji, zakoncz
---

# End of Session (EOS)

Workflow zamykajacy sesje pracy. Bezpieczne zakonczenie z zapisem stanu.

## Workflow

### KROK 0: Handoff (KRYTYCZNY)

**ZAWSZE** zapytaj usera przed zamknieciem:
```
Utworzyc handoff przed zamknieciem sesji? (t/n)
```

Jesli tak → uzyj `/create_handoff` z podsumowaniem sesji.
Jesli nie → kontynuuj do kroku 1.

**UWAGA:** Handoff jest krytyczny - zachowuje kontekst pracy dla przyszlych sesji.

### KROK 1: Eksport stats (KRYTYCZNY jesli skrypt istnieje)

Sprawdz czy istnieje skrypt eksportu:
```powershell
$statsScript = "$env:USERPROFILE\.claude\scripts\export-device-stats.ps1"
if (Test-Path $statsScript) {
    & $statsScript
}
```

**Sciezka skryptu:** `~/.claude/scripts/export-device-stats.ps1`

Jesli skrypt istnieje - MUSISZ go wykonac.
Jesli nie istnieje - pomin (ale poinformuj usera).

### KROK 2: Git commit + push (KRYTYCZNY)

Pobierz summary z argumentow (ARGUMENTS). Jesli brak - zapytaj usera.

```bash
git add .
git commit -m "eos: [ARGUMENTS lub summary od usera]"
git push
```

**WAZNE:**
- Przed git commit pokaz `git status` userowi
- Jesli brak zmian - poinformuj i zakoncz
- Jesli push sie nie uda - poinformuj o bledzie

### KROK 3: Potwierdzenie (KRYTYCZNY)

Po ukonczeniu wyswietl:
```
Sesja zakonczona.
Aby wznowic na innym urzadzeniu:
  git pull && claude && /resume_handoff
```

## Przyklad uzycia

```
/eos auth implementation done
```

Wykona:
1. Zapyta o handoff
2. Eksport stats (jesli skrypt istnieje)
3. `git add . && git commit -m "eos: auth implementation done" && git push`
4. Komunikat o zakonczeniu

## Pelny workflow konca dnia

```
/eos implementacja auth
> Utworzyc handoff? (t)
> [tworzy handoff]
> [eksportuje stats]
> [git commit + push]
> Sesja zakonczona.
```

Na innym urzadzeniu:
```
git pull
claude
/resume_handoff
```
