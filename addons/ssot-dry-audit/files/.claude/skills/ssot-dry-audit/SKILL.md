---
name: ssot-dry-audit
description: Audyt kodu pod katem Single Source of Truth (SSOT) i Don't Repeat Yourself (DRY). PURE AUDIT — generuje raport (markdown + machine-readable YAML) i konczy. Sam NIE naprawia kodu — naprawe deleguje do /petla solve. Wywoluj gdy user prosi o "audyt SSOT", "audyt DRY", "znajdz duplikaty w kodzie", "shotgun surgery", "magic numbers", "redundancja w kodzie", "kod sie powtarza", "duplikacja", "zlamanie DRY", "sprawdz spojnosc kodu". Ma tez TRYB NOCNY (unattended) wolany przez petla-noc modul S — bez AUQ, wynik = kolejka zatwierdzen w .petla-noc/ssot/.
allowed-tools: [Bash, Read, Write, Grep, Glob, AskUserQuestion]
---

# SSOT/DRY Audit (pure audit)

> **SSOT:** kopia INSTALOWANA (`~/.claude/skills/ssot-dry-audit/`) = zrodlo prawdy.
> Mirror dystrybucyjny: `<repo KFG-Addons>/addons/ssot-dry-audit/files/.claude/skills/ssot-dry-audit/`
> — po KAZDEJ edycji SKILL.md/helpera `cp` installed→mirror + `diff -q`.

Skill audytujacy projekt pod katem SSOT/DRY. Generuje **dwa pliki**:
1. `SSOT_DRY_AUDIT_REPORT.md` — czytelny raport dla czlowieka
2. `.ssot-findings.yaml` — maszynowy handoff dla `/petla solve`

Skill NIE naprawia kodu. Naprawa = osobny krok przez `/petla solve .ssot-findings.yaml` lub recznie z markdown.

Tryb bezobslugowy dla petla-noc (modul S): sekcja **TRYB NOCNY** na koncu pliku.

## Output

| Plik | Cel | Lokalizacja |
|------|-----|-------------|
| `SSOT_DRY_AUDIT_REPORT.md` | Czytelny raport dla usera | root projektu (auto-gitignored) |
| `.ssot-findings.yaml` | Strukturalny handoff dla petla solve | root projektu (auto-gitignored) |

## Workflow — 5 faz (inwentaryzacja → skan → analiza → raporty → wywiad decyzyjny)

### Faza 1: Inwentaryzacja

Wykryj typ projektu i zakres skanu.

1. **Project type detection** — uzyj output helpera (`project.types`). Helper wykrywa po markerach: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `appsscript.json`, `Gemfile`, `composer.json`. Walks up to znajdzie marker w przodkach.
2. **Clean tree check (zalecane)** — `git status` przed audytem. Jezeli sa uncommitted changes, ostrzez ze raport bedzie zawieral surowy stan (audyt sam nie tknie kodu, ale user moze chciec audytowac clean state).
3. **Zakres**:
   - Maly projekt (`<20` plikow): pomin pytanie, skanuj wszystko
   - Sredni (20-500): podaj liste glownych folderow, **zapytaj raz** czy zawezic
   - Duzy (`>500`): **OBOWIAZKOWO** zawez razem z userem (np. "tylko `src/components/`")

   Jezeli `$ARGUMENTS` ma wartosc → uzyj jej i pomin pytanie.

### Faza 2: Skan mechaniczny

```bash
python3 ~/.claude/skills/ssot-dry-audit/scripts/detect_duplicates.py <ZAKRES> --output .ssot-scan.json
# --output OBOWIAZKOWO: pelny JSON na stdout przekracza limit outputu narzedzia
# (~30k znakow) na srednich repo -> obcieta polowa dokumentu = falszywy ABORT.
# Stdout = 1-liniowe podsumowanie; pelny wynik czytaj z .ssot-scan.json (gitignored).
# Skanowane rozszerzenia: patrz CODE_EXTENSIONS w helperze (m.in. js/ts/py/gs/html/css/sh).
```

Helper produkuje JSON ze `schema_version: "2.0"`. Zwaliduj kontrakt:

```yaml
{
  "schema_version": "2.0",
  "helper_version": "...",
  "scope": "...",
  "files_scanned": N,
  "files_skipped": N,
  "files_excluded_as_test": N,
  "walk_info": {"dirs_unreadable": N, "dirs_unreadable_sample": [...], "dirs_symlinked_skipped": N, "files_size_skipped": N},
  "truncation": {"<kategoria>": {"returned": N, "total_found": N}, "note": "..."},   # caps 50/30/30/30/20/50 + locations[:10] (locations_total per finding)
  "project": {"types": [...], "project_root": "..."},
  "notes": [...],   # informacyjne stringi (RAW-output disclaimer) — skill ich nie konsumuje
  "findings": {
    "duplicate_strings": [{"value", "secret_kind", "occurrences", "files", "locations_total", "locations"}],
    "duplicate_numbers": [{"value", "is_float", "occurrences", "files", "locations_total", "locations"}],
    "duplicate_function_names": [{"name", "occurrences", "files", "locations_total", "locations"}],
    "duplicate_type_names": [{"name", "occurrences", "files", "locations_total", "locations"}],
    "duplicate_code_blocks": [{"hash", "window_lines", "occurrences", "files", "locations_total", "locations"}],
    "polish_business_ids": [{"kind", "value_redacted", "location"}]
  }
}
```

Jezeli `schema_version` != `"2.0"` lub `findings` brakuje → ABORT z bledem ("helper outdated lub niewiadomy schemat").

Jezeli helper zwroci `error` field → ABORT i pokaz blad userowi (np. path traversal,
pusty skan: `files_scanned == 0` to error helpera, NIE czysty wynik). Sprawdz tez
`walk_info.dirs_unreadable` — niezerowe = skan CZESCIOWY, ujawnij to w raporcie.
Kategorie z `truncation.total_found > returned` → przed propozycja refaktoru RE-GREPNIJ
(helper pokazuje top-N, nie wszystko).

**Persystencja (odpornosc na kompakcje/przerwanie — bez tego przerwana Faza 3 = caly audyt od zera):**
1. Helper z `--output .ssot-scan.json` zapisuje skan BEZPOSREDNIO (atomic tmp+rename) — to JEST artefakt persystencji Fazy 2 (gitignored, patrz 4b); zwaliduj schemat czytajac plik.
2. W Fazie 3 po sklasyfikowaniu kazdej paczki ~10 findingow DOPISZ wynik do `.ssot-findings.partial.yaml` (atomic: tmp + mv).
3. RESUME: `.ssot-findings.partial.yaml` istnieje na starcie → wczytaj, pomin juz sklasyfikowane findingi, kontynuuj od nastepnego; istnieje tylko `.ssot-scan.json` → pomin Faze 2 (skan juz jest) — ALE jezeli plik jest podejrzanie stary albo kod zmienial sie od skanu (git status/mtime), przeskanuj ponownie zamiast resume (stary skan = stare numery linii).
4. Faza 4 po udanym finalnym zapisie raportow USUWA `.ssot-scan.json` i `.partial` (sprzatanie po sukcesie).

**6 kategorii surowych znalezisk:**

1. `duplicate_strings` — string literals (>=3x w >=2 plikach), pre-redacted dla secret-shaped (sk_, eyJ JWT, base64-blob, URL z credentials, GitHub/Slack tokens)
2. `duplicate_numbers` — liczby (>=3x int / >=2x float w >=2 plikach), z flag `is_float`
3. `duplicate_function_names` — funkcje (cross-language: Python/JS arrow/Go/Kotlin/Rust)
4. `duplicate_type_names` — interface/type/class/struct/enum
5. `duplicate_code_blocks` — sliding window 5-linii, sha256[:32]
6. `polish_business_ids` — PESEL/NIP/IBAN znalezione **niezaleznie od duplikacji** (sam fakt hardcoded'u to RODO violation). Od v2.2.0 digit-kinds sa CHECKSUM-walidowane (gole 10/11-cyfrowki bez poprawnej sumy = odrzucone); REGON poza zakresem (inne checksumy); nazwy kindow historyczne (pesel-or-regon11/nip-or-regon)

### Faza 3: Analiza semantyczna

Helper to surowy filtr — zaden helper nie zlapie semantyki. Faza 3 = ty + lektura plikow.

#### 3a. Filtruj false positives helpera

Dla kazdego helper-finding:
1. Czy lokalizacje sa w kontekscie biznesowym, czy boilerplate? (helper juz wyfiltrowal GAS API namespaces, ale moze cos zostalo)
2. Czy fragmenty maja te sama semantyke domenowa? (np. dwa `'admin'` — jeden CSS class, drugi role check → DROP)
3. Czytaj 2-3 najbardziej podejrzane sites ZANIM wpiszesz finding do raportu.
4. Sprawdz `files_excluded_as_test` w JSON helpera — co wykluczono jako testy i czy slusznie (produkcyjne e2e/integration NIE sa wykluczane bez testowej nazwy pliku).

**Heurystyka rankingowa** (czego czytac najpierw):
- `files` desc (duplikat w 5 plikach > 2 plikach)
- Sciezki w `src/` > `utils/` > `helpers/`
- Pomijaj findings ktorych value wyglada na boilerplate (np. zaczyna sie od `http://`, `<svg`, `Mozilla/5.0`)

#### 3b. Szukaj semantycznych SSOT violations (helper ich NIE znajdzie)

1. **Duplicate state** — ta sama wartosc w stanie >1 modulu/komponentu (`currentUser` w 3 React components zamiast w jednym store)
2. **Derived state stored as state** — `fullName` jako pole obok `firstName + lastName`; `total` obok `price * quantity`; `isExpired` obok `expiresAt`
3. **Shotgun surgery risk** — zmiana jednej reguly biznesowej wymaga edycji w wielu plikach (stawka VAT, format telefonu)
4. **Niespojne zrodla** — dwa pola formularza opisujace to samo (`client_email` vs `customer_email`); dwie kolumny w bazie z ta sama semantyka
5. **Konfiguracja rozsiana** — URL-e/klucze/limity inline zamiast w `config`
6. **Lamanie SSOT na granicy systemow** — wartosc z API przepisana recznie zamiast referencjonowana; schema bazy zduplikowana jako TS interface

#### 3c. Polish-business pack (jezeli stack pasuje)

Specyficzne ryzyka dla user's stack (Zoho/GAS/Polish business):

- **Zoho field-name SSOT** — gdy widzisz odwolania do Zoho API (`ZCRM`, `zohoApi.update`, `getRecords`), cross-check API names vs UI labels w kodzie. Z CLAUDE.md: "Field names in Zoho API differ from UI labels" — drift to klasyczny bug.
- **Polish validators** — funkcje zawierajace `pesel`, `nip`, `regon`, `vat`, `walidacja`, `iban` — duplikaty TYCH walidatorow zawsze CRITICAL (regulacja prawna).
- **Polish currency formats** — `'1234,56 zl'`, `'1 234,56 PLN'`, `'1.234,56 PLN'` to TA SAMA wartosc — flag jako "rozne formaty kwoty miedzy modulami".
- **Polish date formats** — `DD.MM.YYYY` vs `YYYY-MM-DD` vs `D MMMM YYYY` — mieszanka w UI/API to source of confusion.
- **VAT rates** — 0.23, 0.08, 0.05, 0.00 (i ich procentowe odpowiedniki 23/8/5) — kazda hardcoded instancja powinna miec rationale w raporcie ("Polski podatek VAT — obowiazek prawny zgodnosci ze stawka").
- **Multi-tenant identifiers** — hardcoded `tenant_id`, `org_id`, slugi typu `'kfg-prod'` — zawsze CRITICAL (data isolation).

#### 3d. Polish business IDs (z helper'a)

Jezeli helper zwrocil `polish_business_ids` (PESEL/NIP/IBAN — checksum-walidowane od v2.2.0) — wszystkie maja status CRITICAL niezaleznie od liczby wystapien. Nawet **jedna** instancja hardcoded'u to:
- RODO Art. 32 violation (PESEL/IP w kodzie)
- Bezpieczenstwo bankowe (IBAN — ryzyko zmiany konta na fakturze)

**WAZNE:** wartosci sa zredagowane (`[REDACTED:pesel]`) w helper output i RAPORTACH. Nigdy nie pisz raw PESEL/NIP/IBAN do raportu.

#### 3e. Pokrycie analizy semantycznej (OBOWIAZKOWE — dowod, ze Faza 3 sie odbyla)

Per kategoria 3b (6 sztuk) + per pozycja 3c (Polish pack, jesli stack pasuje):
zapisz CHECKED+0 / CHECKED+N / UNABLE (z powodem) + liczbe przeczytanych plikow.
Wynik trafia do raportu (sekcja "Pokrycie analizy semantycznej"). Bez tego raport
z samym wynikiem helpera jest NIEODROZNIALNY od raportu po pelnej analizie —
zasada "NIE generuj raportu bez Fazy 3" musi byc weryfikowalna mechanicznie.

### Faza 3.5: Confidence rating

Kazde finding dostaje **HIGH / MEDIUM / LOW**:

| Pewnosc | Kryteria | Co robi /petla solve |
|---------|----------|----------------------|
| HIGH | Identyczna stala primitywna (string/number) >=3x w identycznym kontekscie biznesowym; identyczna definicja typu z identycznymi polami; KAZDA lokacja przeczytana i ma `evidence` (cytat linii) w YAML | auto-fix dozwolony (petla DEGRADUJE HIGH bez evidence do MEDIUM) |
| MEDIUM | Funkcje o tej samej nazwie ale roznych sygnaturach; bloki kodu na roznych zmiennych; type/interface o tej samej nazwie z roznymi polami | non-destructive: AUTO-FIX z commit-tagiem [REVIEW] (przeglad po fakcie); destructive: AskUserQuestion raz |
| LOW | Stringi pozornie identyczne ale w roznych warstwach; liczby przypadkowo te same; bloki w roznych warstwach architektury | POMIN, zostaw pytanie do usera |

**Trzy pytania kontrolne** przy watpliwosci (jezeli nie umiesz odpowiedziec "tak" → downgrade do LOW):

1. **Semantyka biznesowa:** czy oba fragmenty reprezentuja te sama koncepcje domenowa?
2. **Propagacja zmian:** czy zmiana w jednym miejscu ZAWSZE powinna wplynac na drugie?
3. **Walidacja/edge cases:** czy oba fragmenty maja identyczne reguly walidacji i obslugi bledow?

**Krytyczne:** Dla `duplicate_function_names` MUSISZ przeczytac OBA ciala funkcji przed klasyfikacja i zapisac `bodies_compared: true` w YAML (bez tego pola petla degraduje finding do MEDIUM — deklaracja bez sladu nie jest dowodem). Jezeli ciala roznia sie istotnie → force LOW (to nie SSOT, to przypadek nazewnictwa). Helper sprawdza tylko nazwy, nie ciala.

### Faza 4: Raporty

#### 4a. Sanityzacja PRZED zapisem

Zanim cokolwiek zapiszesz na dysk:

1. Zweryfikuj ze zaden code-snippet w "Propozycji refaktoru" nie zawiera:
   - `[REDACTED:*]` markerow z helpera (jezeli zostawiles je w propozycji — usun, redact w propozycji tez)
   - Polskich PII (PESEL, NIP, IBAN) — uzyj `[REDACTED:pesel]` etc.
   - Obviously-secret-shaped wartosci (eyJ*, sk_*, AWS keys)
2. Jezeli musialbys zacytowac secret w "przed/po" code-snippet → uzyj `<REDACTED-VALUE>` placeholder zamiast wartosci.

#### 4b. Auto-gitignore

Przed zapisem raportu:
```bash
# guard: .gitignore bez koncowego newline skleilby nasz wpis z ostatnia regula usera
# (np. '.env' -> '.envSSOT_DRY_AUDIT_REPORT.md' — zepsuta JEGO regula i NASZ wpis)
[ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore
for f in 'SSOT_DRY_AUDIT_REPORT.md' 'SSOT_DRY_AUDIT_REPORT.md.tmp' \
         '.ssot-findings.yaml' '.ssot-findings.yaml.tmp' \
         '.ssot-findings.partial.yaml' '.ssot-scan.json' '.ssot-scan.json.tmp'; do
  grep -qxF "$f" .gitignore 2>/dev/null || echo "$f" >> .gitignore
done
```

User'owi powiedz: "Raporty dodane do .gitignore — nie zostana zaccommitowane."

#### 4c. Markdown report (`SSOT_DRY_AUDIT_REPORT.md`)

Atomic write: zapis najpierw do `SSOT_DRY_AUDIT_REPORT.md.tmp`, potem `mv` na finalne (zabezpiecza przed corrupted output przy interruption).

<!-- <<< SZABLON FORMATU — zastap KAZDA wartosc rzeczywistymi wynikami skanu. TAX_RATE/0.23/SSOT-001/PESEL/'admin' to ILUSTRACJE struktury, NIE findingi do skopiowania. >>> -->

```markdown
# SSOT/DRY Audit Report

Data: <YYYY-MM-DD>
Zakres: <sciezki>
Liczba plikow: <N>
Stack: <project.types>

## Podsumowanie

- Liczba znalezisk: **X** (krytyczne: A, srednie: B, niskie: C)
- Polish PII/business IDs: <N> (zawsze critical)
- Estymowany czas refaktoru: <h>
- Quick wins (<10 min kazdy): [SSOT-005, SSOT-012, ...]

## Znaleziska — krytyczne (RYZYKO BIZNESOWE)

### [SSOT-001] <krotki tytul>

- **Typ:** Duplicate state | Hardcoded value | Derived state | Shotgun surgery | Niespojne zrodla | Konfiguracja rozsiana | Lamanie SSOT na granicy | Polish PII | Multi-tenant id
- **Lokalizacje:**
  - `path/to/file.ts:42`
  - `path/to/other.ts:88`
- **Pewnosc:** HIGH | MEDIUM | LOW
- **Sygnaly potwierdzajace SSOT:** identyczna semantyka domenowa
- **Sygnaly przeciw scaleniu:** (dla MEDIUM/LOW) rozne edge cases
- **Estymowany czas:** ~15 min
- **Opis problemu:** co konkretnie sie powtarza
- **Dlaczego ryzyko:** business impact
- **Propozycja refaktoru** *(HIGH/MEDIUM tylko)* lub **Pytanie do usera** *(LOW)*:
  ```ts
  // przed
  const TAX_RATE = 0.23;
  const tax = 0.23;

  // po
  // src/constants/tax.ts
  export const TAX_RATE = 0.23;
  ```

### [SSOT-LOW-007] (LOW — bez code blocku!)

- **Typ:** Niespojne zrodla
- **Lokalizacje:** `auth.ts:12`, `styles.css:88`
- **Pewnosc:** LOW
- **Estymowany czas:** brak (wymaga decyzji)
- **Pytanie do usera:** Czy `'admin'` w auth.ts (sprawdzenie roli) i `'admin'` w styles.css (klasa CSS) maja byc z jednego zrodla? Jezeli tak — wyciagnij do `constants/roles.ts` i import w obu. Jezeli nie — to pozorny duplikat, ignoruj.

## Znaleziska — srednie
...

## Znaleziska — niskie
(LOW: tylko pytania, bez code blocks — zeby /petla solve nie auto-fixował)

## Polish PII / business IDs (RODO)

(Zawsze critical, value zredagowane)

### [PII-001] PESEL hardcoded
- **Lokalizacja:** `src/seedData.ts:42`
- **Wartosc:** `[REDACTED:pesel-or-regon11]`
- **Ryzyko:** RODO Art. 32 — twarde zakazane przechowywanie PII w kodzie
- **Akcja:** usun, przenies do .env / vault / fixture-only-for-tests

## Czyste obszary

- `src/utils/` — pure functions
- `src/api/auth.ts` — centralne miejsce, dobry SSOT

## Rekomendacje strategiczne

- Brak `src/constants/` — kazdy modul ma wlasne stale
- Brak centralnego store
- Brak typed config

## Pokrycie analizy semantycznej (Faza 3e)

| Kategoria | Wynik | Plikow przeczytanych |
|---|---|---|
| 3b.1 Duplicate state | CHECKED+1 | 4 |
| 3b.2 Derived state stored | CHECKED+0 | 4 |
| ... (wszystkie 3b.1-6 + 3c jesli stack pasuje) | | |
```

**Sortowanie:**
- Po **ryzyku biznesowym** (nie po liczbie wystapien)
- Krytyczne = niespojnosc → bledy biznesowe (kwoty, statusy, uprawnienia, PII)
- Srednie = trudniejsze utrzymanie
- Niskie = kosmetyka

**Filtruj false positives** (kanoniczna lista — nie powtarzaj nigdzie indziej):
- Testy/mocki/fixtures/cypress/playwright/__mocks__ (UWAGA: e2e/integration/spec licza sie jako testy TYLKO razem z testowa nazwa pliku — lustro helpera; src/integration/ to zwykle kod produkcyjny, np. integracje Zoho)
- i18n/locales/translations
- Migracje bazy
- Boilerplate frameworka (helper juz filtruje GAS API namespaces)

**Kazde znalezisko HIGH/MEDIUM ma konkretna propozycje naprawy.** LOW MA TYLKO pytanie, bez code blocku (anty-attractor dla auto-fix).

#### 4d. Machine-readable handoff (`.ssot-findings.yaml`)

# <<< SZABLON — wszystkie id/wartosci ponizej to PRZYKLAD struktury; wypelnij realnymi findingami ze skanu >>>
# REGULA LOCATIONS: locations[] MUSI wyliczac WSZYSTKIE wystapienia wartosci — helper
# przycina (locations[:10], kategorie [:50]/[:30]/[:20]; patrz pole truncation w JSON),
# wiec przed zapisem RE-GREPNIJ wartosc po calym scope i UZUPELNIJ liste. Inaczej
# petla solve naprawi podzbior lokacji i oglosi sukces przy wciaz zdublowanej reszcie.
```yaml
schema_version: "1.0"
audit_date: "YYYY-MM-DD"
scope: "<sciezki>"
report_md: "SSOT_DRY_AUDIT_REPORT.md"
counts:
  total: X
  critical: A
  major: B
  minor: C

findings:
  - id: SSOT-001
    severity: critical
    confidence: HIGH    # auto-fix dozwolony przez petla solve
    type: hardcoded_value
    locations:          # WSZYSTKIE wystapienia (re-grep wartosci POZA capem helpera!) + evidence per lokacja
      - file: "src/pricing.ts"
        line: 12
        evidence: "const TAX_RATE = 0.23;"      # cytat linii = dowod przeczytania (HIGH bez evidence -> MEDIUM)
      - file: "src/invoice.ts"
        line: 88
        evidence: "const tax = price * 0.23;"
    description: "Stawka VAT 0.23 zahardkodowana w 2 miejscach"
    bodies_compared: null   # WYMAGANE true dla duplicate_function_names (dowod "czytaj OBA ciala")
    refactor:
      action: extract_constant
      destructive: false    # klasyfikacja dla gate'u petli; fallback gdy brak: action==delete
      target_file: "src/constants/tax.ts"
      target_name: "TAX_RATE"
      old_value: "0.23"

  - id: SSOT-LOW-007
    severity: minor
    confidence: LOW     # /petla solve POMIJA
    type: ambiguous_duplicate
    locations:
      - file: "src/auth.ts"
        line: 12
      - file: "src/styles.css"
        line: 88
    description: "'admin' w roznych warstwach"
    user_question: "Czy 'admin' w auth.ts i styles.css to ten sam koncept?"
    # LOAD-BEARING: `confidence: LOW` → petla solve POMIJA (gating po WARTOSCI confidence, nie po obecnosci pola).
    # Omijanie `refactor` to defense-in-depth (LOW nie ma code-blocku), NIE mechanizm skip.

  - id: PII-001
    severity: critical
    confidence: HIGH
    type: polish_pii
    pii_kind: pesel-or-regon11
    locations:
      - file: "src/seedData.ts"
        line: 42
    description: "PESEL hardcoded — RODO violation"
    refactor:
      action: remove_hardcoded_pii
      replacement: "process.env.TEST_PESEL or pytest fixture"

# petla solve READS: preflight.require_clean_tree + branch; per-finding: confidence,
# evidence (HIGH bez evidence -> degradacja do MEDIUM), bodies_compared (j.w. dla
# duplicate_function_names), severity (kolejnosc), refactor{} (seed propozycji + destructive gate).
# Pozostale klucze sa ADVISORY/dokumentacyjne — petla ma wlasna logike verify/rollback (per-fix
# subagent verdicts), nie czyta on_test_or_build_failure/max_consecutive_blocked/require_passing_*.
# LOAD-BEARING: top-level klucze `findings` + `petla_solve_rules` to DYSKRYMINATOR formatu
# w petla solve — NIGDY nie zmieniaj ich nazw (zmiana = cichy downgrade do trybu generic,
# w ktorym LOW przestaje byc pomijane). Mapowanie HIGH/MEDIUM/LOW ponizej to advisory echo
# kanonu z petla SKILL.md (Solve Workflow 5a) — przy rozbieznosci wygrywa petla.
petla_solve_rules:
  HIGH: auto_fix
  MEDIUM: auto_fix_with_review_tag   # destructive → AskUserQuestion raz (kanon: petla 5a)
  LOW: skip                          # petla: status skipped_low_confidence (terminal)
  on_test_or_build_failure: rollback_and_block   # advisory (petla rollback jest verdict-driven)
  max_consecutive_blocked: 3                      # advisory
  branch: "refactor/ssot-fix-<YYYY-MM-DD>"        # READ by petla
  preflight:
    require_clean_tree: true                      # READ by petla
    require_passing_tests: warn                    # advisory
    require_passing_build: warn                    # advisory
```

Atomic write: tmp + mv.

### Faza 5: Wywiad decyzyjny (AskUserQuestion — user-mandated 2026-06-11)

Po zapisaniu raportow zbierasz decyzje usera, ktore czynia handoff wykonywalnym
bez powrotow (lekcja sesji cache 2026-06-10: pytania LOW i tak wracaly recznie):

1. **Zrodla pytan** (w tej kolejnosci): kazdy finding LOW (jego `user_question` —
   opcje: warianty naprawy / wontfix / pozniej); kazdy MEDIUM z `destructive: true`
   (pre-akceptacja kierunku — wlasciwy gate i tak strzeli w solve); niejasnosci
   Fazy 3 rozstrzygalne jednym zdaniem usera. **Zero pozycji → pomin Faze 5**
   (nie wymyslaj pytan na sile).
2. **Forma**: AskUserQuestion, max 4 pytania/runde (wiecej → kolejne rundy);
   2-4 konkretne opcje + automatyczne "Other"; rekomendowana opcja PIERWSZA
   z dopiskiem "(Recommended)"; przy kazdym pytaniu file:line + 1 zdanie kontekstu.
   UWAGA na bledne premise: jesli odpowiedz usera podwaza finding — ZWERYFIKUJ
   w kodzie zanim zapiszesz decyzje (przypadek theme_<w>: "brak writera" okazal sie
   blindspotem skanera na klucze dynamiczne).
3. **Update artefaktow PO wywiadzie** (atomic tmp+mv, YAML + 1-liniowe dopiski
   "ROZSTRZYGNIETE:" w MD):
   - "zrob X" → `user_decision` + data, `confidence: HIGH` (decyzja usera = najwyzsza
     pewnosc), `refactor{}` wypelnione wybranym wariantem → solve auto-fixuje;
   - "wontfix" → `status: wontfix` ORAZ wpis do `thoughts/shared/petla/wontfix-ledger.yaml`
     (kanon petli: wpisy ledgera dodaje WYLACZNIE decyzja usera — to jest ten moment);
   - "pozniej" → zostaje LOW + `user_decision: defer` (solve dalej pomija).
4. Wywiad NIE zmienia natury skilla: nadal PURE AUDIT — zero naprawiania kodu.

## Po audycie

Po Fazie 5 pokaz wynik **bez pytania o nastepne kroki** (decyzje juz zebrane;
przypomnienie ponizej to informacja, nie pytanie):

```
Audyt zakonczony. Pliki:
  SSOT_DRY_AUDIT_REPORT.md (X znalezisk: A krytycznych / B srednich / C niskich)
  .ssot-findings.yaml (handoff dla petla solve; decyzje usera z wywiadu WPISANE)

Polish PII: <N> hardcoded id (zawsze critical, wartosci zredagowane)
Quick wins (<10 min): [...]

Naprawa: /petla solve .ssot-findings.yaml
⚠ Najlepiej w NOWYM oknie konwersacji — handoff niesie komplet (lokacje+evidence+
confidence+decyzje), a solve w tym samym oknie placi za caly transkrypt audytu
przy kazdej turze dajac ten sam rezultat. Przypomnienie, nie blokada.
```

## TRYB NOCNY (unattended — dla petla-noc, modul S)

> Wolany WYLACZNIE przez petla-noc (modul S; kontrakt: `petla-noc/modules/S.md` —
> kadencja >=7 dni i plik stanu `.petla-noc/ssot-last-run` sa po stronie modulu S,
> nie tutaj). ZERO interakcji: zadnego AskUserQuestion, zadnych pytan o zakres.
> Nadal PURE AUDIT — zero naprawiania. Bramka zaleznosci modulu S wykrywa ten tryb
> po istnieniu tej sekcji ("TRYB NOCNY") — nie zmieniaj naglowka bez zmiany w S.md.

**Zakres nocny = wylacznie "wyswietlana dana":** SSOT danych pokazywanych userowi
w >=2 miejscach UI (zakladki/ekrany/aplikacje). Generyczna duplikacje kodu (stale,
bloki, nazwy) robi w nocy modul J petli — NIE dubluj jej w tym trybie.

**Delta wzgledem trybu interaktywnego (per faza):**

1. **Faza 1:** zakres podaje wolajacy (modul S); brak → caly projekt. Zadnych pytan
   o zawezenie niezaleznie od rozmiaru. Dirty tree → odnotuj, kontynuuj.
2. **Faza 2:** helper jak zwykle, ale `--output .petla-noc/ssot/scan.json`. Wynik
   sluzy jako SEED kandydatow (duplicate_strings/numbers czesto wskazuja te sama
   dana renderowana w wielu miejscach) — nie jako findingi same w sobie.
3. **Faza 3-noc (discovery kandydatow, zamiast pelnej 3b):**
   a. wczytaj katalog modulu Z: `.petla-noc/zoho-catalog.yaml` (mapa pol Zoho→store) —
      kotwice lineage; nie wywodz zrodel od zera, gdy katalog je zna;
   b. znajdz render-sites: HTML/klient (bindingi, innerHTML/textContent/innerText,
      kolumny tabel, szablony) + backend (pola zwracane do UI w handlerach);
   c. grupuj lokalizacje po ZRODLE — notacja: `zoho:<API-name>` /
      `sheet:<arkusz>!<kolumna>` / `store:<klucz>`;
   d. dla grup >=2 lokalizacji przesledz sciezki odczytu (lineage) → klasa wg rubryki.
4. **Faza 3.5-noc — rubryka lineage** (specjalizacja Fazy 3.5 dla wyswietlanej danej;
   "100% ta sama dana" wynika z dowodu lineage, nie z nazwy zmiennej/etykiety):

   | Klasa | Dowod | Los |
   |---|---|---|
   | PEWNE (must-equal) | lineage obu lokalizacji schodzi do TEGO SAMEGO zrodla, a po drodze jest kopia/cache/osobna transformacja mogaca sie rozjechac (lub juz rozjechana) | kolejka zatwierdzen (hurtem) |
   | PRAWDOPODOBNE | ta sama etykieta/semantyka w UI, lineage niedomkniety (dynamiczne wywolania, sklejane klucze, dwa fetche) | kolejka zatwierdzen (pytanie, pojedynczo) |
   | RACZEJ_NIE | udokumentowane rozne zrodla | POMIJANE — zero pytan (zero babysittingu) |

   **Umiejscowienie frontendowe OBOWIAZKOWE** dla PEWNE/PRAWDOPODOBNE:
   `{aplikacja, ekran/zakladka (nazwa jak widzi ja user), etykieta pola}` + >=2
   lokalizacje z file:line. Kamil zna frontend, nie backend — pytanie bez
   umiejscowienia jest bezuzyteczne. Brak kompletu → DEGRADACJA o klase
   (PEWNE→PRAWDOPODOBNE; PRAWDOPODOBNE→odpada) — wymusza mechanicznie helper.
5. **Faza 4-noc:** kandydatow zapisz do `.petla-noc/ssot/candidates.json`
   (`{"candidates": [...]}`; pola per kandydat: `id?`, `klasa`, `zrodlo`, `lineage`,
   `umiejscowienie{aplikacja,ekran,etykieta}`, `co_z_czym?`,
   `locations[{file,line,evidence}]`, `description`, `user_question?`) i przepusc
   przez mechaniczny rdzen:
   ```bash
   python3 ~/.claude/skills/ssot-dry-audit/scripts/noc_ssot.py \
     --candidates .petla-noc/ssot/candidates.json --ssot-dir .petla-noc/ssot \
     --limit 12 --scope "<zakres>"
   ```
   Helper robi DETERMINISTYCZNIE: degradacje przy brakach umiejscowienia, odrzucenie
   RACZEJ_NIE, fingerprint `sha1(zrodlo|posortowane PLIKI lokalizacji)` (poziom
   plikow — stabilny na dryf numerow linii), dedup wzgledem `ledger.yaml`
   (reported-niezmienione → stlumione; approved/rejected/wontfix → TERMINALNE),
   limit per bieg (PEWNE przodem; ponad limit NIE wchodzi do ledgera → wraca w
   nastepnym cyklu), atomic zapis `findings-<data>.yaml` + `ledger.yaml` (JSON ==
   poprawny YAML; edycje TYLKO helperem / narzedziami JSON-aware) oraz gotowa
   sekcje raportu porannego na STDOUT — wklej ja VERBATIM do raportu modulu S.
   Samotest rdzenia: `noc_ssot.py --selftest` (kontrfaktyki: degradacja, dedup,
   terminal, limit).
6. **Faza 5: POMINIETA.** Kolejke zatwierdzen rozstrzyga sesja DZIENNA (nizej) — noc nie pyta.
7. **Pliki nocne zyja w `.petla-noc/ssot/`** — w tym trybie NIE tworz root-plikow
   `SSOT_DRY_AUDIT_REPORT.md`/`.ssot-findings.yaml` i NIE dopisuj niczego do
   `.gitignore` projektu (polityka wersjonowania `.petla-noc/` nalezy do petla-noc).

**BEZPIECZNIK KOLEJKI (LOAD-BEARING):** kazdy wpis `findings-<data>.yaml` ma
`confidence: LOW` + `user_question` + `night_queue: awaiting_kamil` → `/petla solve`
takie wpisy POMIJA (gating po wartosci confidence — Zasada 3). Noc NIGDY nie
produkuje auto-fixowalnego YAML: approval-first (decyzja Kamila 2026-07-14).

**Poranne domkniecie (sesja dzienna, nie noc):** AUQ nad kolejka (PEWNE hurtem,
PRAWDOPODOBNE pojedynczo; w tresci pytania umiejscowienie frontendowe + `co_z_czym`):
- "tak, scal" → we wpisie: `confidence: HIGH` + `user_decision` + data + `refactor{}`
  (decyzja usera = najwyzsza pewnosc, jak w Fazie 5) oraz
  `noc_ssot.py --ssot-dir <proj>/.petla-noc/ssot --set-status <fp> approved`;
- "nie, osobne dane" → `--set-status <fp> rejected` (TERMINALNE — noc nie zapyta znowu);
- "wontfix" → `--set-status <fp> wontfix` + wpis do wontfix-ledgera petli (kanon Fazy 5).
Zatwierdzone naprawia `/petla solve <sciezka findings-....yaml>` — najlepiej w nowym
oknie. Docelowy kanal decyzji = okno feedback Terminatora (komponent C planu
SSOT-noc); do tego czasu kolejka + AUQ w sesji dziennej.

## Zasady

1. Sortuj po ryzyku biznesowym, nie liczbie wystapien
2. Filtruj false positives (kanoniczna lista w Fazie 4)
3. `confidence` jest POLEM NOSNYM: petla solve gatuje po jego WARTOSCI — KANON mieszka w petla SKILL.md (Solve Workflow 5a): HIGH→auto-fix (wymaga evidence per lokacja, inaczej degradacja do MEDIUM); MEDIUM non-destructive→auto-fix z tagiem [REVIEW], MEDIUM destructive→confirm raz; LOW→skip (terminal skipped_low_confidence). Ta tabela i Faza 3.5 sa LUSTREM petli — przy rozbieznosci wygrywa petla. HIGH/MEDIUM maja refactor field (petla MUSI startowac proposal od refactor), LOW ma tylko user_question (nigdy code block — defense-in-depth, nie mechanizm skip)
4. Polish PII zawsze critical, wartosci zredagowane przed zapisem
5. Confidence obowiazkowy; przy watpliwosci → downgrade do LOW
6. `duplicate_function_names`: czytaj OBA ciala przed klasyfikacja
7. Maly projekt (<20 plikow) → pomin Faze 1 step 3
8. Duzy projekt (>500) → obowiazkowo zawez zakres
9. Raport po polsku, kod cytowany w oryginale
10. Atomic writes (`.tmp` + `mv`); auto-gitignore raporty
11. Nigdy nie pisz raw PESEL/NIP/IBAN/secret do raportu

## Anti-patterns

- NIE generuj raportu bez Fazy 3 (semantyka) — sam grep daje plaski raport
- NIE wpisuj 200 magic numbers do raportu — filtruj do logiki biznesowej
- NIE pisz code blocku w LOW finding (auto-fix attractor)
- NIE proponuj refaktoru "rozbij na mniejsze pliki" (kosmetyka, nie SSOT)
- NIE rob audytu przy WIP (informuj usera ze widzisz dirty tree)
- NIE pisz raw PII/secret do raportu (sanitize przed)
- NIE proboj naprawiac kodu w tym skillu — to czysty audit; naprawe deleguj do `/petla solve`

## Helper

Plik: `~/.claude/skills/ssot-dry-audit/scripts/detect_duplicates.py` v2.0+

Argumenty:
- `path` (default `.`)
- `--max-file-size BYTES` (default 1MB; <1024 odrzucane)
- `--allow-outside-cwd` (off by default; helper odrzuca path traversal poza cwd)
- `--output FILE` (OBOWIAZKOWE w Fazie 2 — atomic tmp+rename; stdout = 1-liniowe podsumowanie)
- `--compact` (JSON bez indentu, ~40% mniejszy)

Helper:
- Walks up project tree dla detekcji typu projektu
- Pre-redaktuje secret-shaped wartosci
- Wykrywa Polish PII jako separate category (RODO)
- Skanuje HTML maskujac markup IN-PLACE (tylko ciala `<script>`/`<style>`; numery linii = oryginalny plik)
- Szanuje `--max-file-size` (nie OOM na minified files)
- Schema versioned (skill zwaliduje przed konsumpcja)

Jezeli helper zwroci `error` field → ABORT z bledem; nie kontynuuj na partial output.

## Przyklady

```
User: "zrob audyt ssot calego projektu"
→ Faza 1: wykryj typ, pytanie o zakres
→ Faza 2: helper, zwaliduj schema
→ Faza 3: filter helper findings + szukaj semantycznych + Polish-business pack
→ Faza 3.5: confidence rating per finding
→ Faza 4: sanityzuj, gitignore, atomic write SSOT_DRY_AUDIT_REPORT.md + .ssot-findings.yaml

User: "audytssot src/components"
→ Skip pytanie o zakres (arg juz podany)

User: "po audycie napraw co sie da"
→ Wykonaj audit (single responsibility: SKILL konczy sie na raporcie)
→ ale USER JUZ POPROSIL o naprawe — ORCHESTRATOR (sesja) bez pytania kontynuuje:
  wywoluje /petla solve .ssot-findings.yaml zaraz po audycie.
  "Skill sie konczy" ≠ "konwersacja sie konczy" — nie porzucaj jawnej prosby usera.
```
