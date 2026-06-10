# Moduł J — DUPLIKACJA MIĘDZY PROJEKTAMI (WYŁĄCZNIE raport)

Cel: te same / prawie te same funkcje utility w wielu projektach → kandydaci
do wspólnej biblioteki GAS. Wydzielenie biblioteki = decyzja RĘCZNA usera —
moduł niczego nie zmienia.

## Wykonanie

1. Skan CAŁEGO projects-root jednym przebiegiem helpera ssot (cross-file =
   cross-project, bo root obejmuje wszystkie projekty):
   `python3 ~/.claude/skills/ssot-dry-audit/scripts/detect_duplicates.py
   <projects-root> --allow-outside-cwd --output
   <projects-root>/.petla-noc-cross/scan-<data>.json`
   (ścieżka POZYCYJNA + --allow-outside-cwd; katalog utwórz; jeśli projects-root
   nie jest zapisywalny — użyj pierwszego projektu `/.petla-noc/reports/`).
2. Filtruj findings na CROSS-PROJECT: `duplicate_function_names` i
   `duplicate_code_blocks`, gdzie `files` wskazują ≥2 RÓŻNE projekty
   (prefiks ścieżki = katalog projektu). ODRZUĆ ścieżki zawierające
   `/.petla-noc/` — skopiowane harnessy/mocki dałyby gwarantowanych fałszywych
   kandydatów (colToIndex, buildMocks...).
3. Dla każdej pary/grupy: subagent czyta WSZYSTKIE ciała (per reguła ssot
   "czytaj OBA ciała przed klasyfikacją) i klasyfikuje:
   - IDENTYCZNE → kandydat-biblioteka (wysoki priorytet),
   - ROZJECHANE KOPIE tej samej intencji → kandydat-biblioteka + tabela różnic
     (która wersja nowsza/pełniejsza — po treści, nie zgaduj dat),
   - przypadkowa zbieżność nazw → odrzuć (odnotuj).
4. Raport per grupa: nazwa, projekty+plik:linia, klasyfikacja, różnice,
   rekomendowana wersja kanoniczna. Sekcja DECYZJE: zbiorcza pozycja
   "kandydaci do biblioteki wspólnej (N grup)" — z ostrzeżeniem, że biblioteka
   GAS = osobny projekt + wersjonowanie + zmiana wywołań na `Lib.f()`.

## Zasady

- ZERO zmian w kodzie (też zero "ujednolicę przy okazji").
- Działa w RED MODE (czysty raport).
- runtime: skan helpera na dużym root może być wolny → time-box pilnowany
  między krokami; partial → dokończ następnej nocy (progress.json
  `modules.J.state: partial` + note ze ścieżką skanu do reuse).
