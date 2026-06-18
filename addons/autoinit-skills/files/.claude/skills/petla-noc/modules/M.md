# Moduł M — FAZA POKRYCIA: mutation-harden + poszerzanie siatki

Cel: wypełnić okno nocy po F→K pracą ACCRETYWNĄ i zachowującą-zachowanie — najpierw
UTWARDZIĆ istniejącą siatkę (czy DYSKRYMINUJE), potem POSZERZYĆ ją na funkcje dotąd
niepokryte (GAS-heavy, klient). Faza dotyka WYŁĄCZNIE testów; kodu źródłowego nie zmienia.

Pętla / budżet okna / model-per-rola / upgrade-harnessu: patrz SKILL.md „FAZA POKRYCIA".
Tu jest procedura aktywności (kolejność wg dźwigni: M1 utwardź → M2 serwer → M3 klient).

## M1. MUTATION-HARDEN (utwardzenie — najwyższa dźwignia)

Dlaczego: test charakteryzujący jest zielony Z KONSTRUKCJI. Bramka „green PRZED i PO"
chroni tylko przed regresją POKRYTEGO zachowania — ale jeśli test nie DYSKRYMINUJE
(przeżywa mutację kodu), gate jest pozorny. To zmechanizowany kontrfaktyk verify-before-done
(„test musi być CZERWONY bez poprawki"), zastosowany do całej siatki.

1. **Kolejność plików:** najpierw `priority_queue` (E/G/K będą je zmieniać → ich gate MUSI
   dyskryminować), potem najstarszy `files[*].mutation.date`, na końcu pliki bez `mutation`.
2. **MECHANIKA** (subagent `model="sonnet"`): per plik
   `node <projekt>/.petla-noc/harness/mutate.js <projekt> --source <plik> --json`.
   Wynik: `{score, killed, survived, invalid, survivors:[{line, op, change, code}]}`.
   (`invalid` = mutant nie skompilował się — wyłączony z mianownika, NIE liczy się jako kill.)
3. **Zapis** `files[plik].mutation = {score, killed, survived, proven, date}`:
   `proven = (score ≥ mutation_min_score) ORAZ żaden survivor nie leży na ENTRY-POINCIE
   pliku` (entry = z map.json: funkcja-wejście / wołana z klienta `google.script.run` /
   trigger / pozycja menu). Plik bez ważnych mutantów (`score=null`) → `proven:true` TYLKO
   gdy nie ma rozgałęzień/arytmetyki (nie ma czego złamać); inaczej `false` + wpis
   „brak testowalnej logiki / wymaga dekompozycji".
4. **OSĄD** (model sesji) — właściwa robota utwardzania, per survivor:
   a. przeczytaj funkcję + linię survivora + zmianę (np. `10 -> 11`, `> -> <=`);
   b. dobierz wejście ROZRÓŻNIAJĄCE oryginał od mutanta (dla `n>10` vs `n<=10` → `n=10`;
      dla `10`→`11` → `n=10`/`n=11`) — wartość, na której kod daje INNY wynik;
   c. DODAJ przypadek do istniejącego `tests/<plik>.test.js`; oczekiwane = wynik OBECNEGO
      kodu (charakteryzacja, nie ocena „jak powinno być");
   d. waliduj: `node harness.js <projekt> --json` musi przejść (zielony na obecnym kodzie —
      czerwony znaczy, że TEST jest błędny, nie kod; popraw test, max 2 iteracje);
   e. re-run `mutate.js --source <plik>` → survivor zabity, score rośnie; zaktualizuj `mutation`.
   Survivor, którego NIE da się zabić bez ZGADYWANIA intencji (funkcja niedeterministyczna,
   I/O na żywo, martwa gałąź) → NIE zgaduj; wpis do raportu
   „survivor nie do zabicia: <plik>:<linia> <op> — <powód>".
5. **Budżet:** przekroczenie okna sprawdzaj MIĘDZY plikami (nigdy w pół edycji testu) →
   zapisz progress, przejdź dalej / zakończ fazę.

## M2. B-SERVER — funkcje dotąd pomijane

Wejście: `map.json` — funkcje używające UrlFetchApp / triggerów czasowych / >300 linii,
które moduł B świadomie POMINĄŁ (B.md pkt 2d). Procedura: `modules/B.md` sekcja
„POKRYCIE GAS-HEAVY" (bogatsze fixtures: `http`, `sheets` z realnymi danymi). Każdy NOWY
test → natychmiast M1 (mutation-harden), inaczej dokładamy zielone tautologie.

## M3. B-CLIENT — logika klienta `.html`

Tylko gdy `client_coverage != off`. Runner: `client-harness.js` (DOM-shim, NIE jsdom).
Procedura: `modules/B.md` sekcja „POKRYCIE KLIENTA". Selektywnie funkcje z LOGIKĄ
(rozgałęzienia, obliczenia, parsowanie); czysty glue (input→`google.script.run`→DOM) →
warstwa SMOKE (DEPLOY NOCNY), NIE unit. Zapis `files[<plik.html>].client_tests`.
Dyskryminacja RĘCZNA (autor dobiera wejście rozróżniające) — `mutate.js` celuje w `.gs`;
automat mutacji klienta = przyszłe rozszerzenie. Klient zostaje za człowiekiem w AUTO-MERGE TIER.

## Wyjścia M

- progress: `files[*].mutation`, `files[*].client_tests`, `modules.M.state` (done/partial+note).
- nowe/wzmocnione testy w `tests/` i `tests-client/` (niecommitowane przez noc — jak B;
  net jest wersjonowany, użytkownik commituje rano).
- raport sekcja „POKRYCIE": per plik score przed→po, survivory zabite / zostały, pliki
  niepokryte, survivory nie-do-zabicia (do decyzji usera). Pliki `mutation.proven==true`
  zasilają sekcję raportu „AUTO-MERGE TIER" (SKILL.md BRAMKA).
