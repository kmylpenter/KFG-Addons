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

### KROK 2: Git status + auto-summary

1. Uruchom `git status --short` aby zobaczyc zmiany
2. Jesli brak zmian - poinformuj i zakoncz
3. Wygeneruj summary automatycznie na podstawie zmian:

**Reguly generowania summary:**
- Nowe pliki (A): "add [nazwa]"
- Zmodyfikowane (M): "update [nazwa]"
- Usuniete (D): "remove [nazwa]"
- Renamed (R): "rename [stara] to [nowa]"
- Grupuj podobne: "add foo, bar, baz" zamiast 3 osobnych
- Max 60 znakow - skracaj jesli trzeba

**Przyklady auto-summary:**
- `A  src/auth.py` + `M  README.md` → "add auth.py, update README"
- `R  old.js -> new.js` → "rename old.js to new.js"
- `M  file1.py` + `M  file2.py` + `M  file3.py` → "update file1, file2, file3"

### KROK 3: Git commit + push

```bash
git add .
git commit -m "eos: [auto-generated summary]"
git push
```

**NIE pytaj usera o summary** - generuj automatycznie.

Jesli ARGUMENTS podane - uzyj ich zamiast auto-summary.

### KROK 4: Potwierdzenie

Po ukonczeniu wyswietl:
```
Sesja zakonczona.
Commit: [hash]
  - [summary]

Aby wznowic na innym urzadzeniu:
  git pull && claude && /resume_handoff
```

## Przyklad uzycia

```
/eos
```

Wykona:
1. Eksport stats (jesli skrypt istnieje)
2. `git status` → auto-summary
3. `git add . && git commit -m "eos: [auto]" && git push`
4. Komunikat o zakonczeniu

## Przed EOS (zalecane)

Jesli chcesz zapisac stan do wznowienia:
```
/create_handoff [opis stanu]
```

Tworzy YAML handoff z kontekstem sesji.

## Pelny workflow konca dnia

```
/create_handoff auth done, next: frontend tests
/eos
```

Na innym urzadzeniu:
```
git pull
claude
/resume_handoff
```
