---
name: ssot-dry-audit
description: Audyt kodu pod katem Single Source of Truth (SSOT) i Don't Repeat Yourself (DRY). PURE AUDIT — generuje raport (markdown + machine-readable YAML) i konczy. Sam NIE naprawia kodu — naprawe deleguje do /petla solve. Wywoluj gdy user prosi o "audyt SSOT", "audyt DRY", "znajdz duplikaty w kodzie", "shotgun surgery", "magic numbers", "redundancja w kodzie", "kod sie powtarza", "duplikacja", "zlamanie DRY", "sprawdz spojnosc kodu".
allowed-tools: [Bash, Read, Write, Grep, Glob]
---

# SSOT/DRY Audit (pure audit)

Skill audytujacy projekt pod katem SSOT/DRY. Generuje **dwa pliki**:
1. `SSOT_DRY_AUDIT_REPORT.md` — czytelny raport dla czlowieka
2. `.ssot-findings.yaml` — maszynowy handoff dla `/petla solve`

Skill NIE naprawia kodu. Naprawa = osobny krok przez `/petla solve .ssot-findings.yaml` lub recznie z markdown.

## Output

| Plik | Cel | Lokalizacja |
|------|-----|-------------|
| `SSOT_DRY_AUDIT_REPORT.md` | Czytelny raport dla usera | root projektu (auto-gitignored) |
| `.ssot-findings.yaml` | Strukturalny handoff dla petla solve | root projektu (auto-gitignored) |

## Workflow — 4 fazy

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
python3 ~/.claude/skills/ssot-dry-audit/scripts/detect_duplicates.py <ZAKRES>
```

Helper produkuje JSON ze `schema_version: "2.0"`. Zwaliduj kontrakt:

```yaml
{
  "schema_version": "2.0",
  "helper_version": "...",
  "scope": "...",
  "files_scanned": N,
  "files_skipped": N,
  "project": {"types": [...], "project_root": "..."},
  "findings": {
    "duplicate_strings": [{"value", "secret_kind", "occurrences", "files", "locations"}],
    "duplicate_numbers": [{"value", "is_float", "occurrences", "files", "locations"}],
    "duplicate_function_names": [{"name", "occurrences", "files", "locations"}],
    "duplicate_type_names": [{"name", "occurrences", "files", "locations"}],
    "duplicate_code_blocks": [{"hash", "window_lines", "occurrences", "files", "locations"}],
    "polish_business_ids": [{"kind", "value_redacted", "location"}]
  }
}
```

Jezeli `schema_version` != `"2.0"` lub `findings` brakuje → ABORT z bledem ("helper outdated lub niewiadomy schemat").

Jezeli helper zwroci `error` field → ABORT i pokaz blad userowi (np. path traversal).

**6 kategorii surowych znalezisk:**

1. `duplicate_strings` — string literals (>=3x w >=2 plikach), pre-redacted dla secret-shaped (sk_, eyJ JWT, base64-blob, URL z credentials, GitHub/Slack tokens)
2. `duplicate_numbers` — liczby (>=3x int / >=2x float w >=2 plikach), z flag `is_float`
3. `duplicate_function_names` — funkcje (cross-language: Python/JS arrow/Go/Kotlin/Rust)
4. `duplicate_type_names` — interface/type/class/struct/enum
5. `duplicate_code_blocks` — sliding window 5-linii, sha256[:32]
6. `polish_business_ids` — PESEL/NIP/REGON/IBAN znalezione **niezaleznie od duplikacji** (sam fakt hardcoded'u to RODO violation)

### Faza 3: Analiza semantyczna

Helper to surowy filtr — zaden helper nie zlapie semantyki. Faza 3 = ty + lektura plikow.

#### 3a. Filtruj false positives helpera

Dla kazdego helper-finding:
1. Czy lokalizacje sa w kontekscie biznesowym, czy boilerplate? (helper juz wyfiltrowal GAS API namespaces, ale moze cos zostalo)
2. Czy fragmenty maja te sama semantyke domenowa? (np. dwa `'admin'` — jeden CSS class, drugi role check → DROP)
3. Czytaj 2-3 najbardziej podejrzane sites ZANIM wpiszesz finding do raportu.

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

Jezeli helper zwrocil `polish_business_ids` (PESEL/NIP/REGON/IBAN) — wszystkie maja status CRITICAL niezaleznie od liczby wystapien. Nawet **jedna** instancja hardcoded'u to:
- RODO Art. 32 violation (PESEL/IP w kodzie)
- Bezpieczenstwo bankowe (IBAN — ryzyko zmiany konta na fakturze)

**WAZNE:** wartosci sa zredagowane (`[REDACTED:pesel]`) w helper output i RAPORTACH. Nigdy nie pisz raw PESEL/NIP/IBAN do raportu.

### Faza 3.5: Confidence rating

Kazde finding dostaje **HIGH / MEDIUM / LOW**:

| Pewnosc | Kryteria | Co robi /petla solve |
|---------|----------|----------------------|
| HIGH | Identyczna stala primitywna (string/number) >=3x w identycznym kontekscie biznesowym; identyczna definicja typu z identycznymi polami | auto-fix dozwolony |
| MEDIUM | Funkcje o tej samej nazwie ale roznych sygnaturach; bloki kodu na roznych zmiennych; type/interface o tej samej nazwie z roznymi polami | wymaga per-finding user confirmation (NIE batch [REVIEW]) |
| LOW | Stringi pozornie identyczne ale w roznych warstwach; liczby przypadkowo te same; bloki w roznych warstwach architektury | POMIN, zostaw pytanie do usera |

**Trzy pytania kontrolne** przy watpliwosci (jezeli nie umiesz odpowiedziec "tak" → downgrade do LOW):

1. **Semantyka biznesowa:** czy oba fragmenty reprezentuja te sama koncepcje domenowa?
2. **Propagacja zmian:** czy zmiana w jednym miejscu ZAWSZE powinna wplynac na drugie?
3. **Walidacja/edge cases:** czy oba fragmenty maja identyczne reguly walidacji i obslugi bledow?

**Krytyczne:** Dla `duplicate_function_names` MUSISZ przeczytac OBA cialA funkcji przed klasyfikacja. Jezeli ciala roznia sie istotnie → force LOW (to nie SSOT, to przypadek nazewnictwa). Helper sprawdza tylko nazwy, nie ciala.

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
grep -qF 'SSOT_DRY_AUDIT_REPORT.md' .gitignore 2>/dev/null || echo 'SSOT_DRY_AUDIT_REPORT.md' >> .gitignore
grep -qF '.ssot-findings.yaml' .gitignore 2>/dev/null || echo '.ssot-findings.yaml' >> .gitignore
```

User'owi powiedz: "Raporty dodane do .gitignore — nie zostana zaccommitowane."

#### 4c. Markdown report (`SSOT_DRY_AUDIT_REPORT.md`)

Atomic write: zapis najpierw do `SSOT_DRY_AUDIT_REPORT.md.tmp`, potem `mv` na finalne (zabezpiecza przed corrupted output przy interruption).

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
```

**Sortowanie:**
- Po **ryzyku biznesowym** (nie po liczbie wystapien)
- Krytyczne = niespojnosc → bledy biznesowe (kwoty, statusy, uprawnienia, PII)
- Srednie = trudniejsze utrzymanie
- Niskie = kosmetyka

**Filtruj false positives** (kanoniczna lista — nie powtarzaj nigdzie indziej):
- Testy/mocki/fixtures/cypress/playwright/e2e/integration/__mocks__
- i18n/locales/translations
- Migracje bazy
- Boilerplate frameworka (helper juz filtruje GAS API namespaces)

**Kazde znalezisko HIGH/MEDIUM ma konkretna propozycje naprawy.** LOW MA TYLKO pytanie, bez code blocku (anty-attractor dla auto-fix).

#### 4d. Machine-readable handoff (`.ssot-findings.yaml`)

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
    locations:
      - file: "src/pricing.ts"
        line: 12
      - file: "src/invoice.ts"
        line: 88
    description: "Stawka VAT 0.23 zahardkodowana w 5 miejscach"
    refactor:
      action: extract_constant
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
    # NIE zawiera 'refactor' field — petla solve sprawdza obecnosc field i pomija jezeli brak

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

petla_solve_rules:
  HIGH: auto_fix
  MEDIUM: per_finding_confirmation
  LOW: skip
  on_test_or_build_failure: rollback_and_block
  max_consecutive_blocked: 3
  branch: "refactor/ssot-fix-<YYYY-MM-DD>"
  preflight:
    require_clean_tree: true
    require_passing_tests: warn
    require_passing_build: warn
```

Atomic write: tmp + mv.

## Po audycie

Pokaz userowi wynik **bez pytania o nastepne kroki** (skill jest pure-audit, decyzja o naprawie nalezy do usera/petla):

```
Audyt zakonczony. Pliki:
  SSOT_DRY_AUDIT_REPORT.md (X znalezisk: A krytycznych / B srednich / C niskich)
  .ssot-findings.yaml (handoff dla petla solve)

Polish PII: <N> hardcoded id (zawsze critical, wartosci zredagowane)
Quick wins (<10 min): [...]

Naprawa: /petla solve .ssot-findings.yaml
```

## Zasady

1. Sortuj po ryzyku biznesowym, nie liczbie wystapien
2. Filtruj false positives (kanoniczna lista w Fazie 4)
3. HIGH/MEDIUM majy refactor field, LOW ma tylko user_question (nigdy code block)
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
- `--max-file-size BYTES` (default 1MB)
- `--allow-outside-cwd` (off by default; helper odrzuca path traversal poza cwd)

Helper:
- Walks up project tree dla detekcji typu projektu
- Pre-redaktuje secret-shaped wartosci
- Wykrywa Polish PII jako separate category (RODO)
- Skanuje HTML poprzez ekstrakcje `<script>`/`<style>` content
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
→ Wykonaj audit, pokaz "Naprawa: /petla solve .ssot-findings.yaml"
→ Skill konczy sie tu, nie wchodzi w naprawe (single responsibility)
```
