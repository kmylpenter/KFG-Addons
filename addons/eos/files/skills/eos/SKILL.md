---
name: eos
description: End of Session - handoff + git commit + push. Triggers: eos, koniec sesji, zakoncz
---

# End of Session (EOS)

Workflow zamykajacy sesje pracy. **Wszystkie kroki sa MANDATORY.**

## Workflow

### KROK 1: Eksport stats

Sprawdz czy istnieje skrypt eksportu:
```powershell
$statsScript = "$env:USERPROFILE\.claude\scripts\export-device-stats.ps1"
if (Test-Path $statsScript) {
    & $statsScript
}
```

Jesli skrypt nie istnieje - przejdz dalej (to OK).

### KROK 2: Git status + auto-summary

1. Uruchom `git status --short` aby zobaczyc zmiany
2. Jesli brak zmian - poinformuj i zakoncz (STOP)
3. Wygeneruj summary automatycznie na podstawie zmian:

**Reguly generowania summary:**
- Nowe pliki (A): "add [nazwa]"
- Zmodyfikowane (M): "update [nazwa]"
- Usuniete (D): "remove [nazwa]"
- Renamed (R): "rename [stara] to [nowa]"
- Grupuj podobne: "add foo, bar, baz" zamiast 3 osobnych
- Max 60 znakow - skracaj jesli trzeba

Jesli ARGUMENTS podane - uzyj ich zamiast auto-summary.

### KROK 3: Create handoff (MANDATORY)

Wywolaj skill `/create_handoff` z wygenerowanym summary:

```
Skill(skill="create_handoff", args="[summary z kroku 2]")
```

LUB jesli Skill tool nie dziala, wykonaj logike recznie:
1. Utworz plik `thoughts/shared/handoffs/[timestamp]-eos.yaml`
2. Zapisz YAML z:
   - `summary`: [auto-summary]
   - `changes`: [lista zmian z git status]
   - `next_steps`: [jesli znane]
   - `timestamp`: [ISO timestamp]

**NIE POMIJAJ TEGO KROKU** - handoff jest wymagany do resume na innym urzadzeniu.

### KROK 4: Git commit + push (MANDATORY)

```bash
git add .
git commit -m "eos: [summary z kroku 2]"
git push
```

**NIE pytaj usera** - wykonaj automatycznie.

Jesli push sie nie uda - poinformuj o bledzie ale NIE przerywaj (handoff juz utworzony).

### KROK 5: Potwierdzenie

Wyswietl:
```
Sesja zakonczona.
Commit: [hash]
Handoff: [sciezka do YAML]

Aby wznowic na innym urzadzeniu:
  git pull && claude && /resume_handoff
```

## Przyklad uzycia

```
/eos
```

Wykona kolejno:
1. Eksport stats (jesli skrypt istnieje)
2. `git status` → auto-summary: "update eos addon"
3. `/create_handoff update eos addon` → YAML handoff
4. `git add . && git commit && git push`
5. Komunikat z instrukcja resume

## Pelny workflow cross-device

**Urzadzenie A (koniec pracy):**
```
/eos
```

**Urzadzenie B (wznowienie):**
```
git pull
claude
/resume_handoff
```
