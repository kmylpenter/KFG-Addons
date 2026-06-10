# Moduł E — SOLVE + KWARANTANNA (jedyny moduł naprawczy; W CAŁOŚCI za bramką)

Dwie części: (E1) naprawy issues z audytu przez /petla solve; (E2) kwarantanna
martwego kodu. Obie wymagają: brak RED, branch sesji, BRAMKA TESTOWA per plik
(kanon: SKILL.md). `--dry-run` → cały moduł raportuje plan, nic nie zmienia.

## E1. SOLVE (reuse /petla solve)

1. Przeczytaj `~/.claude/skills/petla/SKILL.md` → "Tryb: SOLVE". Wykonujesz go na
   `.petla-noc/reports/audit-<projekt>-<data>.yaml`, z różnicami nocnymi:
   - KOLEJNOŚĆ: najpierw `priority_queue` (fresh_debt + criticale z poprzednich
     nocy — mapowanie severity→kolejność), potem critical→major→minor wg petli;
   - BRAMKA per issue: plik(i) dotykane przez fix muszą mieć `tests: green` —
     inaczej issue → status `blocked_no_tests` (nocny odpowiednik blocked; wraca
     gdy B pokryje plik) + wpis do raportu;
   - confidence LOW → skip (per petla 5a); destructive → NIE pytaj (unattended!):
     issue → sekcja DECYZJE raportu ze statusem `needs_human_review`;
   - po KAŻDYM fixie: harness green (bramka pkt 3) → commit `fix` (1 issue =
     1 commit) → verify per petla (lensy solve); fail harnessu → rollback
     (git checkout zmienionych plików) + adnotacja + następne issue;
   - time-box: między issues, nie w środku fix-verify.

## E2. KWARANTANNA MARTWEGO KODU

1. Wejście: issues `gas_category: deadcode` z `quarantine_check` QUALIFIED
   (moduł D / lens gas-deadcode). DOUBT/DISQUALIFIED → raport, NIE ruszaj —
   CHYBA ŻE nazwa figuruje w `progress.quarantine_approved[]` (ręczna akceptacja
   usera z porannego raportu): wtedy traktuj jak QUALIFIED, nadal z obowiązkową
   re-weryfikacją z kroku 2. Funkcje już w `_deprecated.gs` (prefiks DEPRECATED_)
   POMIJAJ — nie re-kwarantannuj kwarantanny.
2. RE-WERYFIKACJA tuż przed ruchem (stan mógł się zmienić): ponów wszystkie
   greps z gas-rules 3 (word-boundary, .gs + .html + stringi) + handler-check +
   (jeśli jest runtime-log.json) zero wykonań 30 dni. Jakikolwiek hit → DOUBT
   → raport. Projekt z sygnałem biblioteki (gas-rules 6) → cała E2 wyłączona.
3. Mechanika kwarantanny (per funkcja; batch max 10 funkcji na commit):
   a. bramka: plik źródłowy ma `tests == green` (kanon BRAMKA pkt 2; bez testów
      → funkcja czeka, raport); dla `_deprecated.gs` wystarczy pełny zielony
      harness PO ruchu (kanon — wyjątek dla plików tworzonych przez moduły);
   b. wytnij PEŁNY blok funkcji (z jej JSDoc) z pliku źródłowego;
   c. dopisz na koniec `<projekt>/_deprecated.gs` (utwórz, jeśli brak):

```js
// ── QUARANTINE <data> ─ from <plik>:<linia> ─ commit <hash-przed> ──
// Revert: git revert <hash-commita-kwarantanny>  (albo przenieś blok z powrotem
// i usuń prefiks DEPRECATED_). Powód: zero referencji (.gs/.html/stringi),
// nie-handler[, 0 wykonań w 30 dni wg runtime-log].
function DEPRECATED_<oryginalnaNazwa>(...) { ...ciało bez zmian... }
```

   d. w ciele przeniesionej funkcji NIE zmieniaj nic poza nazwą w deklaracji;
      wywołania INNYCH funkcji zostają (martwa woła żywe — OK);
   e. martwa funkcja A woła martwą B: kwarantannuj od liści (B najpierw) albo
      razem w jednym batchu — nigdy nie zostawiaj w źródle wywołania do
      DEPRECATED_*;
   f. harness po ruchu green → commit `quarantine` (lista funkcji w message);
      fail → pełny rollback batcha + raport.
4. NIGDY: usuwanie funkcji, usuwanie pliku, kwarantanna handlera/entry pointa,
   zmiana ciała przy okazji ("przy okazji poprawię" → osobne issue do audytu).

## Raport modułu

- E1: per issue → fixed(hash) / blocked_no_tests / needs_human_review / skipped_low.
- E2: per funkcja → quarantined(hash) / DOUBT(powód) / waiting_for_tests.
- Sekcja DECYZJE: wszystkie needs_human_review + DOUBT + kandydaci z runtime_30d=unknown
  (jeśli user chce twardego kryterium 30 dni → moduł P / ręczny eksport).
- Sekcja REVERT: każdy commit z instrukcją.
