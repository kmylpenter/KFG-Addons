---
name: eos
description: End of Session - handoff + stats + project push + history push. Triggers: eos, koniec sesji, zakoncz
---

# End of Session (EOS)

Workflow zamykajacy sesje pracy. Bezpieczne zakonczenie z zapisem stanu.

## MANDATORY STEPS - NIE WOLNO POMINAC

**KRYTYCZNE:** Musisz wykonac WSZYSTKIE 4 kroki w kolejnosci. Pominiecie JAKIEGOKOLWIEK kroku oznacza FAILURE.

## Workflow

### KROK 0: Handoff (MANDATORY - UZYJ SKILL TOOL)

**MUSISZ** uzyc Skill tool z skill="create_handoff":
```
Skill(skill="create_handoff", args="<summary sesji>")
```

**NIE PYTAJ** usera czy chce handoff - **PO PROSTU GO UTWORZ**.
Handoff jest OBOWIAZKOWY dla kazdej sesji EOS.

**BLAD:** Jesli nie uzyles Skill tool dla create_handoff - WRÓC i uzyj go TERAZ.

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

### KROK 2: Git commit + push PROJEKT (KRYTYCZNY)

Pobierz summary z argumentow (ARGUMENTS). Jesli brak - zapytaj usera.

```bash
git add .
git commit -m "eos: [ARGUMENTS lub summary od usera]"
git push
```

**WAZNE:**
- Przed git commit pokaz `git status` userowi
- Jesli brak zmian - poinformuj i kontynuuj do kroku 3
- Jesli push sie nie uda - poinformuj o bledzie

### KROK 3: Push Claude History (MANDATORY)

**MUSISZ** wykonac push historii konwersacji. To jest OBOWIAZKOWE.

```bash
cd "$USERPROFILE/.claude-history" && git add . && git commit -m "eos: [ARGUMENTS lub summary]" && git pull && git push
```

**WAZNE:** `git pull` (merge) jest OBOWIAZKOWY przed push - zapobiega konfliktom gdy wiele terminali robi /eos rownoczesnie. NIE uzywaj `--rebase` - powoduje bledy gdy Claude pisze do plikow w tle.

**UWAGA:** Sciezka to `~/.claude-history/` (NIE `~/.claude/projects/` - to jest junction).

**Jesli git push sie nie uda:**
1. Sprobuj `git pull && git push` jeszcze raz
2. Jesli dalej fail - sprawdz `git status` i pokaz userowi
3. NIE kontynuuj bez udanego push

**BLAD:** Jesli nie pushowales historii - sesja NIE jest prawidlowo zakonczona!

### KROK 4: Potwierdzenie (KRYTYCZNY)

Po ukonczeniu wyswietl:
```
Sesja zakonczona.
- Projekt: [pushed/no changes]
- Claude History: [pushed/not configured]

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
3. Projekt: `git add . && git commit -m "eos: auth implementation done" && git push`
4. Claude History: `cd ~/.claude/projects && git add . && git commit && git push`
5. Komunikat o zakonczeniu

## Pelny workflow konca dnia

```
/eos implementacja auth
> Utworzyc handoff? (t)
> [tworzy handoff]
> [eksportuje stats]
> [git push projekt]
> [git push claude history]
> Sesja zakonczona.
```

Na innym urzadzeniu:
```
git pull
cd ~/.claude/projects && git pull
claude
/resume_handoff
```
