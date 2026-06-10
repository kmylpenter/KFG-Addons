# Moduł G — KONTRAKTY DANYCH KOD↔ARKUSZ (twarde indeksy → header-map)

Cel: znaleźć wszystkie twarde indeksy kolumn i zmapować je na nagłówki arkuszy.
Raport kandydatów do refaktoru na COL (wzorzec: gas-rules 7). Refaktor — TYLKO
za bramką testową, jako zadanie klasy major.

## Wykrywanie (READ-ONLY, subagent per projekt, równolegle)

Wzorce twardych indeksów:
- `row[N]` / `values[i][N]` z literałem N,
- `getRange("C2:C")`, `getRange("A1:D10")` — literały A1 z kolumnami,
- `getRange(r, N[, nr, nc])` z literalnym numerem kolumny N,
- `data[0][N]`, destrukturyzacja pozycyjna wierszy.
Per trafienie zbierz: plik:linia, wyrażenie, arkusz (jeśli wynika z kontekstu —
`getSheetByName("X")` w tej samej funkcji), funkcja.

## Mapowanie na nagłówki (bez dostępu do arkuszy!)

Nagłówki ustalaj WYŁĄCZNIE ze źródeł, w kolejności:
1. stałe w kodzie (`HEADERS`, `var KOLUMNY = [...]`, obiekt COL już istniejący),
2. fixtures testów charakteryzujących (wiersz 0 w fixtures.sheets),
3. komentarze przy kodzie ("// kolumna H = status"),
4. appendRow z literalną tablicą nagłówków (kod tworzący arkusz).
Brak źródła → kandydat BEZ mapowania (raport: "wymaga ręcznego potwierdzenia
nagłówków" → sekcja DECYZJE). NIE zgaduj nazw kolumn.

## Refaktor (opcjonalny, tylko gdy mapowanie pewne)

- Bramka pełna (SKILL.md): testy green przed/po, nie-RED, branch.
- Zakres: jeden plik = jeden refaktor = jeden commit `refactor-headers`.
- Mechanika: wstaw COL (gas-rules 7) raz na plik/funkcję; zamień `row[7]` →
  `row[COL["Status"]]`; literały A1 kolumnowe zostają (zmiana zakresów A1 na
  dynamiczne to WIĘKSZY refaktor → tylko raport).
- Po refaktorze: harness green; fail → rollback + raport.
- Wątpliwość mapowania choć JEDNEGO indeksu w funkcji → cała funkcja report-only.

## Raport

Tabela: plik:linia | wyrażenie | arkusz | nagłówek (lub "?") | refaktor: done(hash)/
kandydat/DECYZJA. Statystyka: ile twardych indeksów, ile zmapowanych, ile zrefaktorowanych.
