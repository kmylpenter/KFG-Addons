---
name: env-doctor
description: Diagnoza i naprawa środowiska Claude (~/.claude) na DOWOLNYM urządzeniu — metodą, nie diffami. Backup → inwentarz → testy żywotności → naprawa lokalnym osądem → werdykt świeżą instancją → zapis wiedzy. Wywołuj po instalacji na nowym urządzeniu, po migracji środowiska (zmiana ścieżek/OS), po upgrade pythona/node, albo gdy "coś przestało działać" w infrastrukturze (recall, hooki, tldr). Triggers: env-doctor, doktor środowiska, napraw środowisko, audyt środowiska claude.
---

# Env Doctor — spójne środowisko Claude na każdym urządzeniu

Cel: po przejściu tego skilla urządzenie spełnia MANIFEST INWARIANTÓW (niżej) i jest to
udowodnione świeżą instancją, nie deklaracją. Naprawiasz **lokalnym osądem** — to samo
zepsucie wygląda inaczej na PRoot/Android, desktopowym Linuksie, macOS i Windows.

## Manifest inwariantów (definicja "działa")

| # | Inwariant | Test |
|---|-----------|------|
| 1 | Learnings: zapis + odczyt roundtrip działa | `store_learning.py` testowy wpis → `recall_learnings.py --text-only` go znajduje |
| 2 | Hook memory-awareness daje MEMORY MATCH | echo JSON \| `hooks/memory-awareness.sh` zwraca poprawny JSON |
| 3 | Self-test zielony | `bash ~/.claude/scripts/infra-selftest.sh` → FAIL=0 (INFO dozwolone) |
| 4 | Żadna reguła w `~/.claude/rules/` nie reklamuje martwego narzędzia | każde narzędzie z reguł przetestowane 1 komendą |
| 5 | Brak osieroconych pamięci | katalogi `~/.claude/projects/*/memory` odpowiadają AKTUALNYM ścieżkom projektów |
| 6 | Hook epistemic-reminder podpięty i w dobrym schemacie | selftest check #6 |

## Procedura

**0. BACKUP (zawsze, przed czymkolwiek):**
```bash
mkdir -p ~/.claude/backups/$(date +%F)-env-doctor && cd ~ && tar -czf ~/.claude/backups/$(date +%F)-env-doctor/baseline.tar.gz .claude/rules .claude/CLAUDE.md .claude/settings.json $(find .claude/projects -maxdepth 2 -name memory -type d 2>/dev/null) 2>/dev/null
```
Niczego nie kasujesz w trakcie całego skilla. Archiwizacja = `mv` do `~/.claude/rules-archive/` + wiersz w tamtejszym README (plik, data, powód, warunek przywrócenia).

**1. Self-test:** `bash ~/.claude/scripts/infra-selftest.sh`. Każdy FAIL → playbook niżej. INFO oceń: czy to "nie dotyczy urządzenia", czy ukryty brak.

**2. Inwentarz reguł:** przejrzyj `~/.claude/rules/*.md`; wynotuj każde narzędzie/usługę/ścieżkę, którą reguły reklamują; przetestuj najtańszą komendą (`command -v`, 1 query). Martwe → napraw albo zarchiwizuj regułę z powodem. Reguła opisująca inną maszynę (np. docker, którego tu nie ma) = szkodliwy kontekst, nie "nieszkodliwa notka".

**3. Osierocone pamięci (po migracji/zmianie ścieżek):** klucz katalogu w `~/.claude/projects/` pochodzi ze ścieżki cwd — po przeniesieniu projektów stare pamięci przestają się ładować. Wykryj pary stary/nowy klucz; migruj KOPIUJĄC (nigdy mv/rm źródła), per projekt; przy kolizjach nazw nie nadpisuj — porównaj i unikalną treść przenieś do `<nazwa>-archiwum-<źródło>.md`. Każdy zmigrowany plik dostaje stopkę: `*(Zmigrowane <data> z <źródło> — zweryfikuj aktualność ścieżek/stanu przed użyciem.)*` + wpis w MEMORY.md celu. Duże katalogi → subagenci równolegle (po jednym na projekt, kontrakt idempotentny: "jeśli plik już ma stopkę X, nie dubluj" — wtedy wznowienie po awarii jest bezpieczne).

**4. Profil urządzenia w regułach:** `rules/dynamic-recall.md` ma sekcję "Device profile" — opisz PRAWDĘ tego urządzenia (backend sqlite/postgres, co istnieje, czego nie ma, data weryfikacji, co unieważnia wpis). Analogicznie sekcja Environment w `~/.claude/CLAUDE.md`.

**5. Re-test + werdykt świeżą instancją (obowiązkowy):**
```bash
bash ~/.claude/scripts/infra-selftest.sh   # musi być FAIL=0
cd ~ && claude -p "Uruchom: bash ~/.claude/scripts/infra-selftest.sh i wklej wynik. Potem odpowiedz czy widzisz reguły successor-calibration i corpus-maintenance. Format: SELFTEST=..., RULES=tak/nie" --allowedTools "Bash"
```
Konfiguracja (hooki, env, reguły) ładuje się NA STARCIE sesji — Twoja bieżąca sesja nie jest dowodem. Dowodem jest odpowiedź świeżej instancji.

**6. Zapis wiedzy:** memory `env-maintenance-<data>.md` w projekcie-korzeniu (co naprawione, czego nie ruszono i czemu, gdzie backup) + `store_learning.py` dla każdej nietrywialnej naprawy (typ ERROR_FIX/WORKING_SOLUTION, treść z DLACZEGO). Raport dla usera nazywa też pominięcia.

## Playbooki napraw (sprawdzone przypadki)

- **`ModuleNotFoundError` w skryptach core (dotenv/httpx/aiosqlite):** menedżer hosta — apt (PRoot/Debian), brew (macOS), pkg (Termux), pip/winget (Windows). Nie twórz venvów, których nikt potem nie aktywuje.
- **Brak `scripts/core/db/memory_service.py` (sqlite backend store'a):** plik jest w payloadzie tego addonu — instalacja addonu go uzupełnia. Kontrakt schematu: czytnik `recall_learnings.py` (FTS5 `archival_fts` + `archival_memory`, `created_at` = epoch float).
- **Embeddings:** jest `DATABASE_URL`/postgres → zostaw (prawdziwe embeddingi). Nie ma → `EMBEDDING_PROVIDER=mock` + `AGENTICA_MEMORY_BACKEND=sqlite` w `settings.json.env` (postinstall addonu robi to add-if-absent; recall i tak chodzi po FTS5, mock to wypełniacz dla dedup-API).
- **tldr martwy:** typowo martwy shebang po upgrade pythona (pip-skrypty wskazują starą wersję) albo `Error: 'gitwildmatch'` (pathspec>=1.0 łamie API). Fix: `uv tool install llm-tldr` (+`UV_LINK_MODE=copy` w PRoot — hardlinki zabronione) + `uv pip install --python ~/.local/share/uv/tools/llm-tldr/bin/python "pathspec<1.0"`. Sprawdź, że `~/.local/bin` wygrywa w PATH ze starą binarką.
- **Hook nic nie wnosi mimo podpięcia:** zły schemat wyjścia jest IGNOROWANY PO CICHU. PostToolUse/UserPromptSubmit: `{"hookSpecificOutput":{"hookEventName":"<Event>","additionalContext":"..."}}`. Testuj hook na sucho: `echo '<input-json>' | node hook.mjs`.
- **`pgrep -f X` w komendzie zawierającej X:** matchuje własny shell → fałszywe "działa". Używaj klasy znaków: `pgrep -f "[X]"`.
- **Granica Termux↔PRoot (Android):** binarki Termuxa przeważnie nie odpalają się z PRoot (inny linker/shebang) — nie wołaj ich pełną ścieżką; instaluj odpowiednik po stronie PRoot.
- **Windows:** selftest odpal w Git Bash; bez Git Bash wykonaj checki manifestu ręcznie (python/py, node, ścieżki przez `%USERPROFILE%\.claude`). Wpis hooka w settings.json używaj ze ścieżką ABSOLUTNĄ (zmienne `$HOME` w komendzie hooka nie rozwijają się na Windows).

## Zasady twarde

1. Backup przed pierwszą zmianą; **zero kasowania** (archiwizacja z powodem i warunkiem przywrócenia).
2. **Nie nadpisuj configu per-urządzenie** (DATABASE_URL, klucze, customowe env) — dlatego add-if-absent, nigdy force.
3. Werdykt "działa" wyłącznie po świeżej instancji (`claude -p`), nie z bieżącej sesji.
4. Raport końcowy nazywa: naprawione / nieruszone+czemu / czekające na decyzję usera.
