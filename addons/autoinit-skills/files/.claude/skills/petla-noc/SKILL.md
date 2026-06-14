---
name: petla-noc
description: "Nocny, w pełni autonomiczny orchestrator sprzątania projektów Google Apps Script: canary testów, mapa zależności (wywołania dynamiczne ze stringów), testy charakteryzujące (Node + mocki), audyt przez /petla audit z lensami GAS, solve + kwarantanna martwego kodu WYŁĄCZNIE za bramką testową, raport poranny z instrukcją revertu. Moduły F→A→B→C→I→G→D→E→(P)→H→J→K. Zero pytań do usera, zero kasowania, zero push do main; deploy WYŁĄCZNIE na dedykowany link NOCNY (auto-tworzony 1. nocy, stały URL — patrz DEPLOY NOCNY)."
version: "1.3"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList, TaskGet, ToolSearch, AskUserQuestion
---

# /petla-noc v1.0 — Nocne sprzątanie projektów Google Apps Script

> Rozszerzenie ekosystemu /petla (audit/solve) o autonomiczną, wielogodzinną sesję
> nocną. Architektura: OSOBNY skill-orchestrator, który REUŻYWA /petla audit (moduł D)
> i /petla solve (moduł E) jako podwykonawców — nie fork, nie nowy tryb petli.
> Uzasadnienie: inny cykl życia (batch z time-boxami i progress.json vs interaktywna
> iteracja do konsensusu), petla ma już ~2700 linii, a kontrakt "noc woła petlę"
> daje jeden format findingów w obu skillach.

---

## INVARIANTS — NEVER VIOLATE

1. **Subagents only.** Jak w petli: każdy walidator/analityk = `Agent(subagent_type=
   "general-purpose")` BEZ `team_name`/`TeamCreate`/`SendMessage` do walidatorów
   (Termux: teammates mrożą tmux — patrz petla SKILL.md "SUBAGENTS ONLY").
2. **UNATTENDED — zero pytań.** ŻADNEGO `AskUserQuestion`, żadnego "czy kontynuować".
   KAŻDA wątpliwość = pomiń + wpis do raportu (sekcja "Pominięte"). NIGDY nie zgaduj.
   JEDYNY WYJĄTEK: MERGE-GATE w KROKU 0 pkt 5 — pytanie pada PRZY STARCIE nocy,
   gdy user (który właśnie ją odpalił) jest jeszcze obecny; po przejściu KROKU 0
   pytania są bezwzględnie zakazane jak dotychczas.
3. **NIC nie jest usuwane.** Martwy kod → kwarantanna: plik `_deprecated.gs` +
   prefiks `DEPRECATED_` w nazwie. Dynamiczne wywołanie starej nazwy ma dać jawny
   błąd "function not found", nie cichą regresję.
4. **Zmiany kodu TYLKO za bramką testową** (patrz BRAMKA niżej) i NIGDY w RED MODE.
5. **Zero push do main.** `clasp push`/deploy WYŁĄCZNIE w ramach sekcji DEPLOY
   NOCNY (dedykowany deployment utworzony przez skill; wyjątek autoryzowany przez
   usera 2026-06-10). Deployment PRODUKCYJNY i TESTOWY usera: NIETYKALNE — deploy
   produkcyjny robi user ręcznie. Skill commituje wyłącznie na `cleanup/<data>`.
6. **Pseudokod = LOGIC SPEC** (jak petla INVARIANT 5) — bloki kodu w tym pliku i w
   modules/*.md odgrywasz narzędziami. WYJĄTKI DO EMISJI: zawartość `templates/`
   (harness, mocki, szkielety raportów) ORAZ kod generowany przez moduły (testy,
   JSDoc, wrapper, __touch) — to są artefakty wyjściowe.
7. **Model per rola** (jak petla INVARIANT 3) — role OSĄDU (moduł D = audyt+lensy,
   weryfikacja, solve E, charakteryzacja B, semantyka G/I, wszystkie MUTACJE w głównym
   kontekście) dziedziczą model sesji, NIGDY downgrade. Read-only analizy czysto
   MECHANICZNE (A mapa zależności, F-diff canary, H skan martwych kluczy Properties,
   J detekcja duplikacji) → `model="sonnet"` (osobny cap; wynik weryfikowalny, wpada
   pod osąd). Nigdy haiku. Rola graniczna: A/B raz przed downgradem. (Rewizja
   2026-06-14: cap teraz wiążący → uwolnione tokeny = więcej nocnych iteracji.)
8. **SSOT:** reguły Apps Script (handlery, wywołania dynamiczne, wzorce) mieszkają
   WYŁĄCZNIE w `shared/gas-rules.md` — każdy moduł je CZYTA, żaden nie kopiuje.
   Skill instalowany (`~/.claude/skills/petla-noc/`) = źródło prawdy; mirror
   dystrybucyjny: `addons/autoinit-skills/files/.claude/skills/petla-noc/` —
   po KAŻDEJ edycji `cp -r` + `diff -r`.

---

## WYMAGANIA TWARDE (nienegocjowalne — od usera, verbatim-faithful)

1. W pełni unattended: zero pytań; wątpliwość = pomiń + raport; nigdy nie zgaduj.
2. Nic nie usuwane — kwarantanna `_deprecated.gs` + `DEPRECATED_`.
3. **BRAMKA:** solve i kwarantanna dozwolone dla pliku/modułu TYLKO gdy istnieją dla
   niego testy charakteryzujące i przechodzą PRZED zmianą oraz PO niej. Bez testów —
   wyłącznie audyt (raport).
4. Stan między sesjami: `progress.json` per projekt **per plik** — kolejne noce
   kontynuują, nie zaczynają od zera.
5. Sesja na branchu `cleanup/<data>`; commity atomowe (jedna kategoria = jeden
   commit); zero push do main; zero clasp push. ZMIANA autoryzowana przez usera
   2026-06-10: dozwolony push+deploy WYŁĄCZNIE na dedykowany deployment NOCNY
   (sekcja DEPLOY NOCNY); main oraz prod/test linki usera bez zmian NIETYKALNE.
6. Raport `NIGHT_REPORT_<data>.md`: co zrobiono, co pominięto i czemu, **lista
   decyzji wymagających ręcznej akceptacji usera**, instrukcja revertu.

Moduły F–K dziedziczą wszystkie powyższe (zasada spójności z UZUPEŁNIENIA).

---

## WEJŚCIE I KONFIGURACJA

```
/petla-noc <projects-root> [opcje]

--projects a,b,c     tylko wskazane projekty (nazwy katalogów)
--dry-run            CAŁA noc w trybie raportowym — żadnych zmian plików/commitów
                     (wyjątek: DEPLOY NOCNY krok D1 — utworzenie linku nocnego,
                     same metadane deploymentu, zero zmian kodu)
--instrument         włącza moduł P (__touch) — domyślnie OFF
--skip J,K           pomiń moduły. F NIE podlega skip (canary obowiązkowy
                     każdej nocy) — KROK 0 odrzuca F z listy + wpis do raportu
--timebox-mult N     mnożnik time-boxów (default 1)
--no-merge-gate      pomiń MERGE-GATE (KROK 0 pkt 5) — do startów przez automat,
                     gdzie nikt nie odpowie na pytanie; działa jak wybór
                     "startuj bez mergowania"
```

- Konfiguracja opcjonalna: `~/.claude/petla-noc.config.yaml`
  (`projects_root:`, `projects: []`, `timebox_mult:`, `instrument:`,
  `red_scope: session|project` — default session) — argumenty CLI wygrywają.
- **Wykrywanie projektów:** katalog bezpośrednio pod projects-root zawierający
  `appsscript.json` LUB ≥1 plik `*.gs`. Zero trafień → STOP z raportem (nie zgaduj).
- **Projekt bez repo git** (lub z BRUDNYM working tree przy starcie): tej nocy
  WYŁĄCZNIE moduły raportowe (zmiany kodu wymagają brancha i czystego punktu
  wyjścia) + wpis do raportu. To odpowiednik trybu degraded petli.

---

## KROK 0: GATE (przed jakąkolwiek pracą)

1. **Deferred tools:** jeśli `TaskCreate/TaskUpdate/TaskList` nie mają załadowanych
   schematów → `ToolSearch("select:TaskCreate,TaskUpdate,TaskList,TaskGet")`.
2. **Walidacja ścieżki** (jak petla KROK 0): REJECT segment `..` przed normalizacją;
   realpath w dozwolonych korzeniach; projects-root zostaje PEŁNĄ ścieżką.
3. **LOCK per projekt** (wykonywany w pkt 4, dla każdego wykrytego projektu):
   `<projekt>/.petla-noc/lock` z PID (format wpisu jak petla KOLIZJE I LOCK).
   Cudzy ŻYWY PID → projekt POMIŃ tej nocy + wpis do sekcji DECYZJE raportu
   ("zajęty przez inną noc, PID <n>"); martwy → przejmij. Zdejmij WSZYSTKIE
   przejęte locki na końcu (też po błędzie). Lock w katalogu projektu = dwie
   noce mogą biec RÓWNOLEGLE na rozłącznych zbiorach projektów; kolizja jest
   per projekt, nie per telefon — nawet przy nakładających się rootach druga
   noc po prostu pomija zajęte. (Zastępuje dawny globalny ~/.claude/petla-noc.lock;
   limity subskrypcji są wspólne dla równoległych nocy — patrz pasek usage-pace.)
4. **Discovery projektów** + na KAŻDY projekt: NAJPIERW przejmij lock (pkt 3;
   pominięte projekty wypadają z tej nocy), potem wczytaj/utwórz
   `<projekt>/.petla-noc/progress.json` (schema: `templates/progress.schema.json`).
   Walidacja `--skip`: jeśli lista zawiera F — usuń F z listy + wpis do raportu
   (canary jest nieskipowalny). Projekt z `.git`: IDEMPOTENTNIE zapewnij
   `<projekt>/.petla-noc/.gitignore` (z `templates/dotgitignore` — allowlist:
   ignoruje stan roboczy progress/map/reports/cache/staging/locki, TRACKUJE net
   `tests/`, `tests-wip/`, `sealed/`, `harness/`). Brak → utwórz; istnieje → nie
   ruszaj. **NIE dopisuj już `.petla-noc/` do `.git/info/exclude`** (porzucone
   2026-06-14: net testów ma być wersjonowany i przenośny między urządzeniami —
   patrz STAN). Stan roboczy i tak ignorowany; ignored/untracked przeżywa checkout
   na base. Starszy blanket-wpis `.petla-noc/` w `.git/info/exclude` → usuń go
   (inaczej `git add` netu wymagałby `-f`).
5. **MERGE-GATE (jedyne dozwolone pytanie do usera — przy starcie, zanim noc
   stanie się bezobsługowa):** per projekt-repo wykryj niezmergowane branche
   poprzednich nocy: `git branch --list 'cleanup/*' --no-merged <base_branch>`.
   Istnieją jakiekolwiek → JEDNO zbiorcze `AskUserQuestion` (lista projekt →
   branche + data) z opcjami:
   a) **Zmerguj teraz** — per projekt, chronologicznie (najstarszy najpierw):
      `git merge --no-ff <branch>` do base_branch LOKALNIE (zero push, jak
      wszystko w nocy); konflikt → `git merge --abort`, zostań przy stanie
      zmergowanym dotychczas, pozostałe branche nieruszone + wpis do raportu
      ("konflikt: <branch> — scal ręcznie rano");
   b) **Startuj bez mergowania** — noc jak dotychczas (świadoma zgoda: audyt
      na base znajdzie częściowo te same problemy co poprzednia noc);
   c) **Przerwij noc** — STOP bez żadnych zmian (user merguje ręcznie).
   Zmergowane/konfliktowe branche → sekcja PORANEK raportu. Brak niezmergowanych
   branchy → ZERO pytania (typowa noc po porannym review). Przy `--dry-run` lub
   `--no-merge-gate`: bez pytania, tylko wykrycie + wpis do raportu (zachowanie
   jak opcja b). Merge wykonaj PRZED pkt 6, żeby `session_base_head` był już
   po scaleniu.
6. **Git per projekt** (jeśli repo, CZYSTE — tzn. bez zmian TRACKED:
   `git status --porcelain -uno` puste; untracked nie blokuje): zapisz do
   progress `base_branch` (bieżący branch) i `session_base_head` (jego HEAD),
   po czym `git checkout -b cleanup/<YYYY-MM-DD>` OD base_branch (istnieje →
   `cleanup/<data>-2`). Zapisz też `session_branch`, `session_start_commit`.
   Noce NIE stackują się: każda odchodzi od base_branch; branche poprzednich
   nocy zostają nietknięte do review. (Exclude `.petla-noc/` już dopisany
   w pkt 4 — dla każdego projektu z `.git`, też brudnego/degraded.)
7. **TaskCreate:** po jednym tasku per (moduł × noc) — `TaskCreate(subject="noc F:
   canary+diff")`, `noc A: mapa`, ... LAZILY w kolejności wykonywania (jak petla
   audit: nie twórz z góry tasków, których time-box może nie dopuścić).
8. **GATE CHECK:** ≥1 projekt PRZEJĘTY (jego `.petla-noc/lock` z naszym PID) + task F
   istnieje → start. Zero przejętych (wszystko zajęte przez inne noce / brak
   projektów) → STOP z raportem.

---

## PRZEBIEG NOCY

**KOLEJNOŚĆ SESJI (twarda):** `F (zawsze pierwszy) → A → B → C → I → G → D → E → (P
jeśli --instrument) → H → J → K`. Sesja przerabia ile zdąży; reszta = następna noc
(progress.json). Wewnątrz modułu: NAJPIERW projekty z niepustą `priority_queue` w progress
(kolejka trzyma issue-id dla modułu E; projekty sortuj wg najwyższej severity
w ich kolejce — mapowanie severity→kolejność), potem pozostałe wg najstarszego
`last_visited`.

| Moduł | Co robi | Zmienia kod? | Bramka | Time-box (min) |
|---|---|---|---|---|
| F | canary testów + diff-audyt świeżego długu | nie | — | 20 |
| A | mapa zależności (map.json) | nie | — | 40 |
| B | testy charakteryzujące | nie (dodaje testy) | — | 60 |
| C | JSDoc z mapy A | TAK (komentarze) | comment-only-diff | 30 |
| I | połykane błędy: raport; wrapper per plik | raport nie / wdrożenie TAK | testy pliku | 30 |
| G | kontrakty kod↔arkusz (row[7]→COL) | raport nie / refaktor TAK | testy pliku, klasa major | 30 |
| D | audyt: /petla audit + lensy GAS | nie | — | 60 |
| E | solve + kwarantanna martwego kodu | TAK | testy pliku + kwalifikacja | 90 |
| P | __touch() instrumentacja (opt-in) | TAK | testy pliku | 20 |
| H | config/sekrety + martwe klucze Properties | nie | — | 20 |
| J | duplikacja między projektami | nie | — | 25 |
| K | var→const/let + ARCHITECTURE/CHANGELOG | TAK | testy pliku, commit per plik | 30 |

Wykonanie modułu = `TaskUpdate(in_progress)` → przeczytaj `modules/<X>.md` +
`shared/gas-rules.md` → wykonaj → zapisz progress.json → `TaskUpdate(completed)`.
Analizy READ-ONLY (A, D, F-diff, G/H/I/J-raport) fan-outuj na subagenty RÓWNOLEGLE
per projekt; KAŻDA mutacja plików — sekwencyjnie, w głównym kontekście.

**MODEL PER MODUŁ (INVARIANT 7):** read-only analizy czysto mechaniczne **A, F-diff,
H, J** → spawnuj z `model="sonnet"` (osobny cap). **D (audyt+lensy)**, B, G, I oraz
wszystkie mutacje (C, E, P, K, wdrożenia I/G) → model sesji (Opus/Fable), **nigdy
downgrade** — tam żyje osąd konsensusu.

### 🔴 RED MODE (RED-TESTS RULE)

```
F wykrywa czerwone testy charakteryzujące → RED GLOBALNY (cała SESJA — verbatim
  usera: "sesja NIE wykonuje żadnych modułów zmieniających kod").
  Złagodzenie do RED per projekt WYŁĄCZNIE po jawnym opt-in usera
  (petla-noc.config.yaml: `red_scope: project`); pierwszy raport z takim configiem
  odnotowuje odstępstwo w sekcji DECYZJE.
W RED: NIE wykonujesz modułów zmieniających kod — E, G-wdrożenie, I-wdrożenie, K, P.
  Moduły raportowe (F, A, B*, C, D, H, J, G/I-raport) działają normalnie.
  (*B dodaje testy — dozwolone; nowe testy nie zmieniają kodu źródłowego.
   C zmienia tylko komentarze — dozwolone per lista usera, comment-only-diff obowiązuje.)
Fail testów = PIERWSZA pozycja NIGHT_REPORT (z hashem commita-winowajcy, jeśli
  bisect był tani) — do porannej decyzji usera.
```

### BRAMKA TESTOWA (kanon — moduły wskazują tutaj)

Zmiana kodu w pliku `X.gs` projektu jest dozwolona TYLKO gdy WSZYSTKIE:
1. Nie ma RED MODE (globalnego ani tego projektu).
2. `progress.files["X.gs"].tests == "green"` — istnieją testy charakteryzujące
   pokrywające plik i CAŁY harness projektu przechodzi PRZED zmianą
   (`node <projekt>/.petla-noc/harness/harness.js <projekt>` → exit 0).
3. Po zmianie harness przechodzi PONOWNIE (exit 0). Fail → `git checkout` zmienionych
   plików (rollback), wpis do raportu, issue wraca do kolejki z adnotacją.
4. Projekt ma branch sesji (nie jest degraded).
Wyjątek — pliki TWORZONE/uzupełniane przez moduły (`_deprecated.gs`, `_errors.gs`,
`_touch.gs`): nie mają własnych testów i mieć nie muszą — wymagany jest TYLKO
zielony PEŁNY harness PO zmianie (harness ładuje wszystkie .gs, więc błąd w nich
obala run). Warunek tests==green z pkt 2 dotyczy plików MODYFIKOWANYCH.
Wyjątek C (JSDoc): zamiast pkt 2-3 wystarczy walidacja comment-only-diff
(`git diff` zmienionego pliku zawiera WYŁĄCZNIE linie komentarzy/puste) + harness
green jeśli testy istnieją. Bez żadnych testów w projekcie C nadal dozwolony
(komentarze nie zmieniają semantyki), pozostałe moduły kodu — NIE. To
INTERPRETACJA wymagania twardego 3 (verbatim mówi o solve i kwarantannie) —
pierwsza noc wpisuje ją do sekcji DECYZJE raportu do potwierdzenia przez usera.

### TIME-BOX

Każdy moduł ma time-box (tabela; × `--timebox-mult`). Mierz od startu modułu
(`date +%s` przy TaskUpdate in_progress). Przekroczenie sprawdzaj MIĘDZY plikami/
projektami (nie przerywaj w pół edycji): przekroczony → zapisz progress.json
(`modules.<X>.state: partial` + note co zostało), wpis do raportu "time-box,
kontynuacja następnej nocy", przejdź do następnego modułu. Noc NIGDY nie utknie na jednym
projekcie/module.

---

## STAN MIĘDZY SESJAMI

```
<projekt>/.petla-noc/
  progress.json        # per plik: tests none|partial|green|red, moduły done/partial,
                       # priority_queue[], last_green_commit, session history
  map.json             # moduł A (graf wywołań + dynamiczne + entry pointy)
  tests/               # testy charakteryzujące (*.test.js): moduł B + sealed-stable (/domknij)
  tests-wip/           # sealed WIP (/domknij) — POZA canary; red≠regresja (F1b)
  sealed/manifest.json # SSOT zapięć /domknij (status/data/pokrycie per feature)
  harness/             # skopiowany z templates/harness przy pierwszym B
  runtime-log.json     # opcjonalny (moduł P / ręczny eksport usera)
  reports/             # audit-<data>.yaml (format petli!), inne artefakty
NIGHT_REPORT_<data>.md # w projects-root (zbiorczy dla wszystkich projektów)
```

- `.petla-noc/` ma **wersjonowany net** (`tests/`, `tests-wip/`, `sealed/`, `harness/`)
  i **ignorowany stan roboczy** (progress/map/reports/cache/staging/locki) — przez
  committowany `.petla-noc/.gitignore` (KROK 0 pkt 4; rewizja 2026-06-14, dawniej cały
  katalog był poza gitem przez `.git/info/exclude`). Net jest przenośny (komputer = tablet
  po `git pull`); stan roboczy lokalny/regenerowalny. Ignored/untracked przeżywa checkout
  na base oraz "nie merguję" — wymaganie twarde 4 nie zależy od porannej decyzji usera.
  Review robisz z dysku (.petla-noc/reports/) + zbiorczy NIGHT_REPORT w projects-root.
- Schema progress: `templates/progress.schema.json`. Przy niezgodności/uszkodzeniu:
  NIE truncate — zrób kopię `.bak-<data>`, odbuduj ze źródeł: git (base_branch,
  commity nocy), map.json (lista plików), re-run harnessu (statusy tests),
  guard D1 (deployment id). Git NIE ma kopii progress (stan poza gitem) —
  dlatego odbudowa jest wieloźródłowa; wpis do raportu.
- **COMPACTION RECOVERY:** po kompakcji kontekstu: `TaskList()` + progress.json
  każdego projektu + partial NIGHT_REPORT → wznów od pierwszego niedokończonego
  modułu. Nie zaczynaj od nowa, nie pytaj.

---

## GIT I COMMITY (kategorie atomowe)

Jedna kategoria zmian = jeden commit (per projekt). Messages EN:

| Kategoria | Kiedy | Format message |
|---|---|---|
| jsdoc | moduł C | `noc(<proj>): jsdoc for <pliki>` |
| quarantine | moduł E | `noc(<proj>): quarantine N dead functions -> _deprecated.gs` |
| fix | moduł E solve | `noc(<proj>): fix <issue-id> <skrót>` (1 issue = 1 commit) |
| refactor-headers | moduł G | `noc(<proj>): header-map COL refactor in <plik>` |
| error-wrapper | moduł I | `noc(<proj>): withErrorLog wrapper in <plik>` |
| instrument | moduł P | `noc(<proj>): __touch instrumentation in <pliki>` |
| syntax-modern | moduł K | `noc(<proj>): var->const/let in <plik>` (1 plik = 1 commit) |
| docs | moduł K | `noc(<proj>): ARCHITECTURE.md + CHANGELOG.md` |

Stan `.petla-noc/` (progress/map/testy/raporty) NIE jest commitowany — żyje
poza gitem (patrz STAN). Commitujesz wyłącznie pliki aplikacji + docs.

Każdy commit zmieniający kod ląduje w raporcie z instrukcją revertu
(`git revert <hash>` lub opis ręcznego cofnięcia kwarantanny).

---

## DEPLOY NOCNY (jedyny dozwolony deploy; przedostatni krok nocy)

> ZMIANA WYMAGANIA TWARDEGO 5 — autoryzowana przez usera 2026-06-10: skill MOŻE
> `clasp push` + deploy, ale WYŁĄCZNIE na dedykowany deployment NOCNY, który sam
> utworzył. Deployment produkcyjny i testowy usera oraz branch main: NIETYKALNE.
> User identyfikuje linki po OSTATNICH 3 ZNAKACH deployment ID ("deploy na DMW",
> "na 9.2DS") — `last3` zawsze w raporcie i progress.json.

ZANIM sprawdzisz warunki: `progress.head_restored == false` → wykonaj D2-wyjątek
(zaległe przywrócenie HEAD) BEZWARUNKOWO — to naprawa stanu chmury po awarii
poprzedniej nocy, nie deploy nowej (biegnie też przy RED/braku commitów).

WARUNKI (którykolwiek pada → deploy POMINIĘTY + powód w raporcie; NIE pytaj):
- projekt nie-degraded, nie ma RED, istnieje `.clasp.json`, clasp dostępny;
- ≥1 commit zmieniający kod tej nocy (inaczej nie ma czego wystawiać — D1 wolno);
- autoryzację clasp weryfikuje D2 (nieudany pull = brak auth → skip + raport);
- `--dry-run`: wykonuje się WYŁĄCZNIE D1 (utworzenie linku = metadane
  deploymentu serwujące dotychczasowy HEAD; zero zmian kodu).

**D1 — PIERWSZA NOC** (progress nie ma `night_deployment_id`): NAJPIERW guard
idempotencji — `clasp deployments`: jeśli istnieje już deployment z opisem
"petla-noc", PRZEJMIJ go (zapisz jego id/url/last3) zamiast tworzyć duplikat
(chroni przed utratą progress.json z dowolnego powodu). Brak → utwórz deployment
z opisem "petla-noc" (`clasp deploy -d "petla-noc"`; dokładne flagi potwierdź
w `clasp help` — wersje clasp różnią się CLI). Zapisz do progress:
`night_deployment_id`, `night_deployment_url`, `night_deployment_last3`
(ostatnie 3 znaki ID). URL + last3 → sekcja PORANEK raportu, wyróżnione.
Od tej pory NIGDY nie twórz nowego deploymentu — wyłącznie aktualizuj ten (`-i`).

**D2 — OCHRONA HEAD CHMURY** (edycje robione w edytorze online ≠ git!):
`clasp pull` do KATALOGU TYMCZASOWEGO (`${TMPDIR:-$HOME/tmp}/noc-pull-<proj>`,
NIGDY do repo) → porównaj treść z base_branch (normalizuj rozszerzenia .js/.gs
wg `fileExtension` z .clasp.json). RÓŻNICE → user ma w chmurze zmiany spoza
gita → DEPLOY POMINIĘTY + raport ("zrób clasp pull do repo i scommituj").
Pull nieudany = brak auth/dostępu → skip + raport. Sprzątnij katalog tymczasowy.
WYJĄTEK po awarii D4 (`progress.head_restored == false`): różnice są OCZEKIWANE
— jeśli pull == tip POPRZEDNIEGO cleanup brancha (to nasz kod nocny), wykonaj
zaległe przywrócenie (push base, `head_restored: true`) i kontynuuj; jeśli pull
≠ tamten tip (user edytował NA kodzie nocnym) → skip + DECYZJE ("ręczne scalenie").

**D3 — WYSTAW NOC** (z brancha cleanup/<data>): `clasp push -f` → utwórz wersję
("petla-noc <data>") → przepnij deployment nocny na tę wersję
(`clasp deploy -i <night_deployment_id> -V <numer>`). URL się NIE zmienia.
Zapisz `last_night_version` do progress.

**D4 — PRZYWRÓĆ HEAD** (triggery i /dev usera wracają na kod bazowy):
`git checkout <base_branch>` → `clasp push -f`. Okno ekspozycji HEAD na kod
nocny: sekundy-minuty w środku nocy; wersja nocna pozostaje PRZYPIĘTA do linku
nocnego (wersje GAS są niemutowalne). (TOCTOU D2→D4 świadomie zaakceptowane —
edycja online w tym oknie jest skrajnie mało prawdopodobna.)
AWARIA D4 (push padł — sieć/auth): retry 1×; nadal fail → `progress.head_restored:
false` + wpis na SZCZYCIE sekcji PORANEK: "⚠ HEAD chmury = kod nocny! Wykonaj:
`git checkout <base>` && `clasp push -f`" — bez tego triggery produkcyjne chodzą
na kodzie nocnym. Sukces D4 → `head_restored: true`.
Sekcję PORANEK uzupełniaj PO D4 — raport finalizowany jako ostatni artefakt nocy.

**ROLLBACK** (zawsze w sekcji PORANEK): jeden ruch —
`clasp deploy -i <night_deployment_id> -V <poprzednia-wersja>`.

---

## NIGHT_REPORT_<data>.md (szkielet: templates/NIGHT_REPORT.md)

Kolejność sekcji OBOWIĄZKOWA:
1. **🔴 RED / CANARY** — czerwone testy (projekt, test, commit-winowajca z bisect
   jeśli tani, zakres commitów jeśli nie). Pusta sekcja = "wszystkie testy zielone".
2. **☀️ PORANEK — link nocny** — URL deploymentu nocnego + **last3** + numer
   wersji + status deployu (wykonany/POMINIĘTY z powodem) + rollback jednym
   poleceniem + lista "co klikać" (funkcje dotknięte przez fixy/kwarantanny).
3. **DECYZJE DO TWOJEJ AKCEPTACJI** — wszystko, czego skill nie zrobił z ostrożności
   (kandydaci na kwarantannę bez kompletu warunków, refaktory G, wrapper I,
   propozycje CONFIG z H, biblioteka z J).
4. **WYKONANE** — per projekt per moduł, z hashami commitów.
5. **POMINIĘTE + DLACZEGO** — każda wątpliwość/skip/time-box/degraded.
6. **REVERT** — tabela commit→jak cofnąć.
7. **STATYSTYKI + PLAN NA NASTĘPNĄ NOC** (z progress.json: co partial, priority_queue).

---

## MODUŁY (specyfikacje: modules/<X>.md — czytaj przed wykonaniem)

- **F — CANARY + DIFF SENTINEL** (zawsze pierwszy): pełny harness wszystkich
  projektów z testami; fail → RED + bisect od `last_green_commit` (jeśli tani:
  ≤8 commitów i testy <60s); diff-audyt kodu zmienionego od ostatniej sesji
  (świeży dług łapany w 24h). Bootstrap: zanim B zbuduje testy, część canary jest
  pusta — działa tylko diff-audyt. SEALED (F1b): testy `tests/sealed_*` (z /domknij)
  jadą w canary jak kontrakty (red=RED, prowenancja „USER-SEALED" w raporcie) i
  ODBLOKOWUJĄ bramkę pliku; `tests-wip/` puszczane informacyjnie, NIGDY RED.
- **A — MAPA ZALEŻNOŚCI**: graf funkcja→funkcja + WSZYSTKIE wywołania dynamiczne
  (triggery/menu/google.script.run/handlery wg gas-rules) + entry pointy → map.json.
  Wejście dla wszystkich pozostałych. Aktualizowana co noc (re-parse zmienionych).
- **B — TESTY CHARAKTERYZUJĄCE**: utrwalają OBECNE zachowanie (X→Y), nie poprawność.
  Node + mocki (templates/harness). Czysta logika najpierw.
- **C — JSDOC**: opis + źródła wywołań (z map.json) + side-effecty. Comment-only-diff.
- **D — AUDYT**: protokół `/petla audit` (czytaj ~/.claude/skills/petla/SKILL.md)
  z 5 lensami GAS z modules/D.md; wynik = audit YAML w formacie petli →
  `.petla-noc/reports/`. Kategorie GAS: batch ops, hardkodowane ID, brak error
  handling wokół API, funkcje >200 linii, SSOT/DRY.
- **E — SOLVE + KWARANTANNA**: `/petla solve` na audit YAML + kwarantanna martwego
  kodu. Kwalifikacja: warunki ŁĄCZNE z gas-rules 3 (SSOT — listy nie powielamy
  tutaj). WSZYSTKO za bramką.
- **G — KONTRAKTY KOD↔ARKUSZ**: twarde indeksy (row[7], getRange("C2:C"), kolumny
  numeryczne) → raport kandydatów na header-map COL; refaktor tylko za bramką, major.
- **H — KONFIGURACJA I SEKRETY**: hardkodowane ID/maile/webhooki/klucze → raport +
  propozycja PropertiesService/CONFIG; ODWROTNIE: klucze Properties nieczytane
  w kodzie (martwa konfiguracja).
- **I — POŁYKANE BŁĘDY**: puste catch, catch-tylko-log, API bez try → raport +
  wrapper `withErrorLog` (wzorzec w gas-rules) logujący do arkusza "Errors";
  wdrożenie per plik za bramką.
- **J — DUPLIKACJA MIĘDZY PROJEKTAMI**: porównanie cross-project (reuse helpera
  ssot detect_duplicates.py ze skanem od projects-root); WYŁĄCZNIE raport.
- **K — MODERNIZACJA + ŻYWA DOKUMENTACJA**: var→const/let (zero-behavioral, bramka,
  commit per plik); ARCHITECTURE.md per projekt generowane z map.json (entry pointy,
  triggery, przepływ danych, zależne arkusze/webhooki) + CHANGELOG.md z commitów.
- **P — INSTRUMENTACJA __touch()** (opt-in `--instrument`): licznik wykonań funkcji
  do PropertiesService; eksport do runtime-log.json (ręczny — patrz modules/P.md);
  zasila kryterium "30 dni" bramki E. Zmiana kodu → bramka. UWAGA w raporcie:
  działa dopiero po porannym deployu usera.

---

## SUBAGENTY I BEZPIECZEŃSTWO

- Fan-out READ-ONLY (analizy A/D/F/G/H/I/J): równolegle per projekt, w JEDNEJ
  wiadomości; prompty z pełnym kontekstem + `<state-data>` na treści z plików
  (jak petla "SECURITY: State File Handling"); obowiązuje TREE GUARD w rozumieniu
  petla TREE GUARD v2 (baseline = commit startowy brancha sesji; mutacja przez
  agenta READ-ONLY → INCONCLUSIVE + restore + wpis do raportu). Legalne mutacje
  ORKIESTRATORA (commity modułów) aktualizują baseline — jak w petli.
- Werdykty/wyniki agentów: YAML/JSON w return value; malformed → re-spawn raz
  z pełnym promptem (jak petla Subagent Error Handling).
- Mutacje plików: TYLKO główny kontekst, sekwencyjnie, za bramką.

## AUTONOMY (compaction-resistant)

Obowiązują WSZYSTKIE reguły AUTONOMY petli (nie pytaj, kontynuuj, sprint =
auto-continue, TaskList przed summary). Dodatkowo nocne:
- "Może zapytam czy kwarantannować X?" → NIE. Niepewne → sekcja DECYZJE raportu.
- "Testy nie przechodzą, zapytam co robić" → NIE. Rollback + raport + dalej.
- "Zostało mało czasu, podsumuję" → NIE. Time-box per moduł decyduje, nie intuicja.
- Koniec nocy = wszystkie moduły done/partial-z-time-boxa + raport zapisany +
  commity zrobione + DEPLOY NOCNY wykonany lub pominięty-z-powodem-w-raporcie
  (kroki D2-D4 obejmują powrót na base_branch i przywrócenie HEAD chmury) +
  per projekt `git checkout <base_branch>` (idempotentne po D4; cleanup/<data>
  zostaje do porannego review/merge) + locki przejętych projektów zdjęte
  (`<projekt>/.petla-noc/lock`). ŻADEN inny warunek nie kończy sesji (poza Ctrl+C).
