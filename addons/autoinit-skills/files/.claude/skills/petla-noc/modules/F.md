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
   - **Prowenancja (sealed):** dla każdego `failures[].file` z JSON odczytaj pole
     `sealed.status` METODĄ JS-AWARE — pliki testów to moduły JS (klucz `status:`, NIE
     `"status":`), więc grep w stylu JSON nic nie znajdzie. Użyj:
     `node -e "console.log((require('<abs>/.petla-noc/tests/<plik>').sealed||{}).status||'none')"`
     (fallback grep: `status:[[:space:]]*["'](stable|wip)["']`). `stable` → w sekcji 🔴 oznacz
     „🔴 USER-SEALED CONTRACT broken (<feature>) — regresja zachowania POTWIERDZONEGO przez
     usera dnia <accepted>" (głośniej niż zwykły test B, bo łamie kontrakt z akceptacji, nie
     tylko zrzut z kodu). Brak pola `sealed` / test B → standardowy wpis. Testy z `tests-wip/`
     NIGDY tu nie trafiają (poza canary — F1b pkt 3).
4. exit 2 (setup error harnessu) → NIE jest RED zachowania; wpis "harness broken"
   do raportu + plikom projektu status tests=red w progress (bramka zamknięta).
5. **Bootstrap:** projekt bez testów → canary pusty (odnotuj w raporcie:
   "canary: brak testów, moduł B w kolejce"). Działa tylko F2.

## F1b. SEALED — testy z /domknij (prowenancja, odblokowanie bramki, WIP)

Testy zapięte przez `/domknij` (interaktywny skill końca sesji, NIGDY nie wołany przez noc)
żyją w dwóch miejscach: `tests/sealed_*.test.js` (STABLE — kontrakt) i
`tests-wip/sealed_*.test.js` (WIP — zrzut). Każdy niesie pole `sealed:{status, accepted,
feature, level, coverage}` (harness je ignoruje — czyta tylko `file:` i `tests`).

1. **STABLE są JUŻ w canary.** `tests/` zawiera sealed-stable obok testów B — F1 puszcza je
   tym samym harnessem; ich złamanie = RED jak każdy kontrakt (prowenancja: F1 pkt 3). ZERO
   osobnego przebiegu. To jest siatka, o którą noc opiera regresję przy refaktorze/kwarantannie.
2. **Odblokowanie bramki (sealed jako pokrycie):** po canary GREEN, dla każdego
   `.petla-noc/tests/*.test.js` odczytaj jego deklarację `file:` przez
   `node -e "console.log(require('<abs>').file)"` (plik testu to moduł JS — JSON-grep zawiedzie). Ustaw
   `progress.files[<file>].tests = green`, jeśli nie jest już `green` — TAKŻE gdy pokrycie
   pochodzi WYŁĄCZNIE z sealed (B nie ruszał tego pliku). Dzięki temu E/G/I/K mogą
   refaktorować/kwarantannować plik oparty o siatkę z `/domknij`. Traktowanie sealed = B na
   potrzeby bramki jest ŚWIADOME: realną ochroną i tak jest „harness green PO zmianie" (BRAMKA
   pkt 3 w SKILL.md) — zmiana łamiąca zachowanie zapięte przez sealed cofnie się jak każda
   regresja. Reszta ryzyka (zmiana funkcji NIEpokrytej w tym pliku) jest identyczna jak przy
   testach B i akceptowana tak samo. NIE downgrade'uj istniejącego `green`/`partial`.
3. **WIP — przebieg INFORMACYJNY (nigdy RED):** jeśli `.petla-noc/tests-wip/` istnieje i
   niepusty: `node <projekt>/.petla-noc/harness/harness.js <projekt> --tests
   .petla-noc/tests-wip --json`. Wynik → sekcja DECYZJE/POMINIĘTE raportu jako informacja
   („sealed WIP: N zielonych, M czerwonych — feature w rozwoju, NIE regresja"). Czerwony WIP
   **NIGDY** nie włącza RED MODE ani nie zamyka bramki — to zrzut stanu, nie kontrakt; decyzja
   stable↔wip należy do usera w `/domknij`. Brak katalogu → pomiń bez wpisu.

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
