# Moduł F — CANARY + DIFF SENTINEL (zawsze pierwszy krok wykonawczy nocy)

Cel: (1) wykryć regresje zachowania ZANIM noc cokolwiek zmieni; (2) złapać świeży
dług techniczny w ≤24h od powstania.

## F1. CANARY — pełny harness testów

1. Dla każdego projektu z testami (`.petla-noc/tests/*.test.js` istnieją):
   `node <projekt>/.petla-noc/harness/harness.js <projekt> --json`.
   Projekty niezależne → odpalaj równolegle (Bash, krótkie procesy).
2. exit 0 → zapisz w progress.json: `last_green_commit = HEAD`, `last_green_date`.
3. exit 1 (fail) → **RED GLOBALNY** (cała sesja; per projekt WYŁĄCZNIE gdy user
   ustawił `red_scope: project` w config — patrz SKILL.md RED MODE, tam kanon).
   Następnie bisect, JEŚLI TANI:
   - kandydaci = commity `last_green_commit..HEAD` na gałęzi roboczej projektu;
   - tani ⇔ ≤8 commitów ORAZ pojedynczy run harnessu <60 s;
   - `git bisect start HEAD <last_green_commit>` + `git bisect run sh -c
     'node <wt>/.petla-noc/harness/harness.js <wt>; rc=$?; [ $rc -eq 2 ] &&
     exit 125 || exit $rc'` (exit 2 harnessu = setup error → 125 KAŻE bisectowi
     POMINĄĆ commit zamiast uznać go za zły; całość na KOPII worktree —
     `git worktree add` — żeby nie ruszać stanu projektu!). PRZED `git bisect
     run` skopiuj stan do kopii: `cp -r <projekt>/.petla-noc <wt>/` — stan żyje
     POZA gitem, świeży worktree go NIE ma; bez kopii harness "missing" = exit 1
     na każdym commicie i bisect wskaże fałszywego winowajcę;
   - wynik (hash winowajcy) → sekcja 🔴 raportu; nietani → podaj ZAKRES commitów.
   - Po bisect: `git bisect reset` + `git worktree remove` (sprzątanie obowiązkowe).
4. exit 2 (setup error harnessu) → NIE jest RED zachowania; wpis "harness broken"
   do raportu + plikom projektu status tests=red w progress (bramka zamknięta).
5. **Bootstrap:** projekt bez testów → canary pusty (odnotuj w raporcie:
   "canary: brak testów, moduł B w kolejce"). Działa tylko F2.

## F2. DIFF SENTINEL — audyt świeżego długu

1. Zakres: `git diff --name-only <last_session_commit>..<session_base_head>
   -- '*.gs' '*.html'` (oba z progress.json; session_base_head = HEAD base
   brancha zapisany w KROK 0 — zakres liczony na BASE, nie na cleanup/;
   pierwszy run = pomiń F2, zapisz punkt).
2. Zmienione pliki → MINI-AUDYT tylko na nich: spawn subagentów z lensami GAS
   z modules/D.md (te same prompty, scope = lista zmienionych plików).
   To ŚWIADOME uproszczenie pełnego protokołu /petla audit (one-shot bez pętli
   konsensusu — time-box F); przy małym diffie (≤3 pliki) MOŻESZ zamiast tego
   odpalić pełny protokół D ze scope=diff.
   Wyniki: issues z tagiem `fresh_debt: true` dopisz (append, dedup po
   file:line+item) do `.petla-noc/reports/audit-<projekt>-<data>.yaml`.
3. `fresh_debt` criticale/majory → na początek `priority_queue` w progress.json
   (mapowanie severity→kolejność: świeży dług naprawiany przed starym).
4. Po UKOŃCZENIU F2 (zakres skonsumowany): `last_session_commit =
   session_base_head`. Nie zapisuj wcześniej — przerwana noc zgubiłaby zakres;
   nie zapisuj HEAD cleanup-brancha — następna noc liczy diff na BASE.

## Wyjścia F

- progress.json zaktualizowany (last_green_commit / RED flags / priority_queue).
- Sekcja 🔴 raportu wypełniona (lub "wszystkie testy zielone").
- RED → lista modułów wyłączonych tej nocy w raporcie.
