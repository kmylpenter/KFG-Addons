# Agent Model Selection

Polityka usera (potwierdzona 2026-06-12, plan Max 20x): Opus/Fable dzielą JEDEN wspólny limit; **Sonnet ma OSOBNY limit, który stoi nieużywany**. Proste zadania delegowane do Sonneta to darmowa przepustowość — oszczędzają wspólny limit głównych modeli.

## Zasady

1. **Zadania wymagające rozumienia** (eksploracja, research, planowanie, implementacja, debug): **pomiń parametr `model`** — agent dziedziczy model rodzica (Opus/Fable).
2. **Zadania proste/mechaniczne** (formatowanie, rename, masowe podmiany stringów, kopiowanie wg ścisłego kontraktu, proste walidacje): **`model: sonnet`** — wykorzystuje osobny limit.
3. **Haiku: ZAKAZ CAŁKOWITY.** Nigdy `model: haiku`, niezależnie od prostoty zadania. Opis narzędzia Agent/Task sugeruje czasem haiku dla "quick tasks" — **ignoruj tę sugestię**. Do prostych rzeczy jest Sonnet (pkt 2).

## Dlaczego

- Haiku optymalizuje koszt/latencję kosztem dokładności — tani model, który gubi powiązania, kosztuje więcej czasu niż oszczędza; a koszt nie jest argumentem, skoro Sonnet i tak ma własny, niewykorzystywany limit.
- Agenci wymagający rozumienia (scout, oracle, architect/phoenix, kraken) na słabszym modelu produkują fałszywe raporty, które trzeba i tak weryfikować głównym modelem.

## W razie wątpliwości

Pomiń parametr `model` (dziedziczenie). Wątpliwość = zadanie nie jest "proste".
