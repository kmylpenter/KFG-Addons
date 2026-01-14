---
name: eos
description: End of Session - eksport stats + git commit + push. Triggers: eos, koniec sesji, zakoncz
---

# End of Session (EOS)

Workflow zamykajacy sesje pracy. Bezpieczne zakonczenie z zapisem stanu.

## Workflow

### KROK 1: Eksport stats (opcjonalny)

Sprawdz czy istnieje skrypt eksportu:
```powershell
$statsScript = "$env:USERPROFILE\.claude\scripts\export-device-stats.ps1"
if (Test-Path $statsScript) {
    & $statsScript
}
```

Jesli skrypt nie istnieje - pomin ten krok (to OK).

### KROK 2: Git commit + push

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

### KROK 3: Potwierdzenie

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
1. Eksport stats (jesli skrypt istnieje)
2. `git add . && git commit -m "eos: auth implementation done" && git push`
3. Komunikat o zakonczeniu

## Przed EOS (zalecane)

Jesli chcesz zapisac stan do wznowienia:
```
/create_handoff [opis stanu]
```

Tworzy YAML handoff z kontekstem sesji.

## Pelny workflow konca dnia

```
/create_handoff auth done, next: frontend tests
/eos auth implementation
```

Na innym urzadzeniu:
```
git pull
claude
/resume_handoff
```
