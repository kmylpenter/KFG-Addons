# Moduł A — MAPA ZALEŻNOŚCI (map.json; wejście dla WSZYSTKICH pozostałych modułów)

Cel: graf wywołań funkcja→funkcja + KOMPLET wywołań dynamicznych + entry pointy.
Wzorce dynamiczne: WYŁĄCZNIE z `shared/gas-rules.md` sekcje 1-2 (SSOT — nie kopiuj).

## Wykonanie

1. Inwentarz: `Glob <projekt>/**/*.gs` + `**/*.html` (poza `_deprecated.gs` —
   mapowany osobno z flagą `deprecated: true`).
2. Re-parse INKREMENTALNY: parsuj tylko pliki zmienione od `map.generated_at`
   (mtime/git diff); resztę przenieś ze starej mapy. Pierwsza noc = wszystko.
3. Per plik (subagent per projekt, równolegle; pliki >2k linii czytaj fragmentami):
   - definicje funkcji (wzorce: gas-rules sekcja 10) → name, file, line, end_line,
     length_lines, `top_level: true` dla kodu poza funkcjami;
   - wywołania statyczne wewnątrz ciał (gas-rules 10) → krawędzie calls[];
   - wywołania dynamiczne (gas-rules 2) → dynamic_refs[] {kind, file, line, raw};
   - stringi będące nazwami funkcji (callback-string) → string_refs[].
4. Scal: called_by[] (odwrotność calls + dynamic + string), entry_point =
   handler specjalny LUB cel dynamic_ref LUB top-level. Funkcje bez called_by
   i bez entry_point → `dead_candidate: true` (TYLKO kandydat — kwalifikację
   robi moduł E wg gas-rules 3). Funkcje z `_deprecated.gs` (`deprecated: true`)
   NIGDY nie dostają dead_candidate — już są w kwarantannie.
5. Zapisz `<projekt>/.petla-noc/map.json`:

```json
{
  "schema": "noc-map-1",
  "generated_at": "...", "source_commit": "...",
  "files": {"Kod.gs": {"top_level": true, "lines": 12345}},
  "functions": [{
    "name": "wyslijRaport", "file": "Kod.gs", "line": 120, "end_line": 180,
    "length_lines": 61, "calls": ["pobierzDane"], "called_by": ["onOpen"],
    "dynamic_refs": [{"kind": "menu", "file": "Kod.gs", "line": 15}],
    "string_refs": [], "entry_point": false, "handler": false,
    "dead_candidate": false, "uses_gas_api": ["SpreadsheetApp", "MailApp"]
  }]
}
```

6. Walidacja przed zapisem: liczba sparsowanych definicji ≥ liczba trafień
   grep `^function ` (sanity); różnica → wpis do raportu (parser coś pominął,
   doubt-rule: pliki z różnicą NIE dostają dead_candidate).

## Konsumenci

B (wybór kandydatów na testy: pure-logic = puste uses_gas_api), C (JSDoc: źródła
wywołań), D/E (dead_candidate + kontekst), K (ARCHITECTURE.md). map.json żyje
w `.petla-noc/` poza gitem (SKILL.md STAN) — bez commitu.
