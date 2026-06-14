# TOOLS_POTENTIAL — pomiar potencjału (2026-06-14)

**Pytanie:** które czynności Claude wykonuje wielokrotnie *rozumowaniem LLM*, a deterministyczny skrypt (zero inferencji) zrobiłby za darmo — żeby odzyskać miejsce pod capem Max 20x?

**Metoda:** deterministyczny skrypt `tools_potential_analyze.py` nad 437 plikami JSONL (`~/.claude/projects/`, okno 7 dni: 2026-06-07 → 2026-06-14). Zero czytania logów rozumowaniem. Token-attribution per tura, rozdział cap MAIN (Opus/Fable) vs SONNET. Pomiar uzupełniony rozmiarami gorących plików (`wc`).

---

## ⚠️ WERDYKT (szczerze, na górze)

**NIE buduj dedykowanego skilla „pętla-narzędzie" dla powtarzalnych komend bash. Netto jest marginalne.**

Powód w jednej liczbie: **realne netto z otoolowania mechanicznych komend ≈ 0,46 % tygodniowego capa.** Brutto wygląda na ~10 % outputu, ale po odjęciu nieredukowalnego (decyzja *czego* szukać + interpretacja wyniku) zostaje ~2,7 % outputu = **0,5 % capa**. To koszt budowy, utrzymania i ryzyka większy niż zysk.

**Dwa twarde fakty, które przewracają intuicję:**

1. **Cap NIE jest zdominowany przez output Claude'a.** W jednostkach kosztu (input-equivalent) tydzień MAIN to ~1245M units, z czego:

   | składnik | cost-units | udział |
   |---|---:|---:|
   | cache_read (replay kontekstu) | 545.8M | **43.8 %** |
   | cache_creation | 469.8M | **37.7 %** |
   | output (rozumowanie Claude'a) | 213.6M | 17.2 % |
   | input_new | 16.1M | 1.3 % |

   **81 % capa to replay kontekstu**, nie rozumowanie. Mechaniczne komendy bash to już *darmowa egzekucja* (grep/sed/git/node nie kosztują inferencji). Otoolowanie ich rusza tylko ~17 % tortu (output), a w nim tylko cienki redukowalny plasterek.

2. **Jedyne narzędzie dotykające dominującego kosztu (replay) JUŻ ISTNIEJE i jest nieużywane.** `tldr` (structure/search/context) w oknie 7 dni: **~29 realnych wywołań. `grep` z basha: 1990.** Problem nie jest „brak narzędzia" — jest „nawyk + brak wiringu w promptach subagentów". To naprawa wiringu, nie budowa.

**Co realnie warto zrobić** (sekcja na końcu): wymusić indeks/section-extract zamiast pętli `grep→sed→re-Read` po wielkich plikach — to jedyna dźwignia sięgająca cache (potencjał 6–11 % capa, ale niepewny i w większości realizowalny istniejącym `tldr`).

---

## Funnel redukowalności (dlaczego brutto ≠ netto)

```
MAIN output 7d:                                    42.7M tok   (100%)
 ├─ tury text-only (12 770) = czyste rozumowanie    ~irredu.   ← nie kandydat
 ├─ Edit 5.5M + Write 1.6M + Agent 2.5M + Task* 1.8M ~11M      ← autorstwo/osąd, nie kandydat
 ├─ ... reszta rozumowania zadaniowego
 └─ POWIERZCHNIA „egzekucja narzędzia" = Bash 7.4M + Read 2.8M ≈ 10.2M
       └─ mechaniczne-deterministyczne (brutto)              ≈ 4.16M  (9.7% output)
             └─ NETTO po odjęciu decide-what + interpret     ≈ 1.14M  (2.7% output)
                   = 5.7M cost-units = 0.46% tygodniowego capa
```

**Brutto/Netto = 3.6×.** Każdy kandydat poniżej wygląda 3–4× lepiej w surowych zliczeniach niż jest naprawdę. To jest właśnie pułapka, przed którą prosiłeś ostrzec.

> **Uwaga o mierze `out_proxy`:** to output całej tury podzielony równo na jej tool_use'y. Tura „thinking + 1 grep" przypisuje grepowi *całe* rozumowanie (też to o zadaniu, nie o grepie). Czyli `out_proxy` to **górna granica** redukowalnego kosztu — nawet brutto jest hojne, netto jest poniżej.

---

## RANKING kandydatów (wg NETTO)

### #1 — Indeks symboli + ekstraktor sekcji dla wielkich plików (pętla `grep -n → sed -n → re-Read`)
- **Czynność:** lokalizacja kodu w plikach GAS/HTML/JS po 2–18 tys. linii przez iteracyjny `grep -n "wzorzec" plik` → `sed -n 'A,Bp' plik` → ponowny `Read` całego pliku.
- **Dlaczego (częściowo) mechaniczne:** mapowanie `symbol → plik:linia` i „pokaż blok wokół symbolu" jest deterministyczne (stabilne wejście→wyjście). **Wyłączone z redukcji:** *co* szukać i *interpretacja* znaleziska — to NLU, zostaje przy LLM.
- **Wystąpienia (7d):** `grep` 1990 + `sed -n` 282; bigram `grep→grep` **1256** (re-szukanie bo pierwszy wzorzec chybił), `grep→sed`/`sed→grep` ~250. Re-ready tych samych plików: **3307 redundantnych** (WorkTime.js 391×, newflow.html 346×, Code.gs 287×, index.html 217×). Projekty: TimeTrackingApp, Terminator-Umowy, KFG-Addons, UtilityHub, TheOldWorld, subagents.
- **BRUTTO:** output ~3.2M (grep+sed+część Read) **+ cache: re-ingest top-6 plików do 221M tok (upper bound)**.
- **NETTO:**
  - output: **~0.6–0.9M** (redukowalna tylko pętla re-szukania; jeden lookup indeksu zostaje, interpretacja zostaje).
  - cache: **~44–77M tok** (20–35 % re-readów to *targeted lookups*, które indeks skróciłby z całego pliku do ~60 linii; reszta to audyty całoplikowe, których indeks NIE skraca) = **6–11 % capa**.
- **Pewność:** output MEDIUM, cache **LOW** (nie znam z logów, czy Read był pełny czy z offset/limit — stąd „upper bound"; realny zysk zależy od udziału lookupów vs audytów całoplikowych).
- **Haczyk:** narzędzie **już istnieje** (`tldr structure/search`, Grep tool). Używane ~29× vs grep 1990×. To głównie wiring/nawyk, nie budowa.

### #2 — Bundla stanu repo (`git status` + `diff` + `log` + `branch` → 1 wywołanie)
- **Czynność:** read-only zapytania o stan gita, odpalane seriami.
- **Dlaczego mechaniczne:** czysto deterministyczny odczyt stanu. **Wyłączone:** interpretacja diffa.
- **Wystąpienia:** ~460 read-only git (`diff` 254, `show` 93, `log` 60, `status` 54); bigram `git→git` 265. Wszystkie projekty.
- **BRUTTO:** ~310k output proxy.
- **NETTO:** **~100–150k** output (zwinięcie 2–3 tur w 1) + drobna oszczędność cache z ~265 mniej tur. = ~0.06 % capa.
- **Pewność:** MEDIUM.

### #3 — Powtarzalne skrypty-ekstraktory inline (`node -e` / `python3 <<HEREDOC` autorowane od nowa)
- **Czynność:** wczytaj plik/JSON, regex-wyłuskaj sekcję/wartość — Claude pisze ten sam kształt skryptu za każdym razem.
- **Dlaczego (częściowo) mechaniczne:** gdy *kształt się powtarza* (ten sam plik, ta sama sekcja) — np. `node -e "...readFileSync('newflow.html')...match(/<script>.../)"` **22×**, `cd Terminator/GAS && python3 - <<HEREDOC` 11×. **Wyłączone:** jednorazowe, nowe ekstrakcje (to autorstwo = rozumowanie).
- **Wystąpienia:** ~230 `node -e`/`python3` inline; redukowalne tylko powtarzalne ~80–120.
- **BRUTTO:** ~500k output proxy.
- **NETTO:** **~150–250k** output (tylko powtarzalne kształty → nazwany skrypt znosi re-autorstwo). = ~0.1 % capa.
- **Pewność:** LOW-MEDIUM (granica „powtarzalne vs nowe" jest miękka).

### #4 — Deterministyczne walidatory/liczniki (`node --check`, `wc -l`, `md5sum`, `diff`, pre-check przed `clasp push`)
- **Czynność:** walidacja składni JS, liczenie linii, checksumy, porównania plików.
- **Dlaczego mechaniczne:** czyste, zero osądu.
- **Wystąpienia:** `node --check` (część z 465 `node`), `wc` 61, `diff` 59, `md5sum` 5, `clasp push` 24.
- **BRUTTO:** ~150k output proxy.
- **NETTO:** **~60–90k** output. = ~0.03 % capa.
- **Pewność:** MEDIUM.

### (poza rankingiem) #5 — `cd`/`echo` boilerplate — **PUŁAPKA POMIAROWA, netto ≈ 0**
- W surowych zliczeniach `cd` = 774 wywołań / **1.6M output proxy**, `echo` = 437 / 793k — wygląda jak top kandydat.
- **To artefakt:** „cd" łapie *wieloliniowe skrypty* zaczynające się od `cd ścieżka\n<python/node heredoc>` — 1.6M to **te same ciała heredoców co #1/#3, doppelt liczone**. Sam `cd /x && ` to ~5 tokenów. Realne netto ≈ 0. Pokazane jawnie, bo to modelowy przykład „kandydat wygląda lepiej niż jest".

---

## Wykluczone (osąd / język naturalny — zostają przy LLM, nie są kandydatami choćby się powtarzały)

| Czynność | output (proxy) | dlaczego nie |
|---|---:|---|
| `Edit` / `Write` (autorstwo kodu) | 7.1M | generowanie kodu = rdzeń rozumowania |
| Tury text-only (12 770) | duże | wyjaśnienia/decyzje |
| `Agent` spawn + `TaskCreate/Update` | 4.3M | dekompozycja zadań = planowanie |
| Decyzja *czego* greppować, *czy* to duplikat | — | NLU |
| Interpretacja diffa / wyniku grepa | — | NLU |
| Treść komitów, `AskUserQuestion` | 0.24M | język naturalny |
| Zapytania `recall_learnings.py` (149×) | — | skrypt JUŻ istnieje; *query* jest NLU |

---

## Bonus (dotyczy Twojego celu „odzyskać cap", choć to nie deterministyczny skrypt)

**SONNET ma osobny cap i stoi pusty:** output SONNET = 155k vs MAIN 42.7M (**0,36 %**). Potwierdza Twoją politykę. Wniosek operacyjny ważniejszy niż cały powyższy ranking: czynności *pół-mechaniczne, które JEDNAK wymagają LLM* (np. „czy to duplikat", klasyfikacja, proste ekstrakcje z osądem — wykluczone ze skryptowania) **deleguj do Sonneta**, nie pal ich na MAIN. To zerokosztowa przepustowość, która odciąża wspólny cap bez budowania czegokolwiek.

**Subagenci to 21 % outputu MAIN (8.9M) i większość redundantnych re-readów** (każdy startuje na zimno i re-czyta SKILL.md 359× / WorkTime.js 316× / Code.gs 243×). Największy pojedynczy zysk z #1 jest tutaj: wstrzyknięcie indeksu/section-extract do promptów `petla`/`petla-noc`, żeby subagent czytał 60 linii zamiast pliku po 195k tok.

---

## Co realnie zrobić (bez budowy nowego skilla)

1. **Używaj `tldr structure`/`search` zamiast pętli `grep→sed→re-Read`** po plikach >1500 linii. Narzędzie jest, działa (`/root/.local/bin/tldr`), używane 29× vs grep 1990×. To jedyna dźwignia sięgająca cache (81 % capa).
2. **Wstrzyknij ten nawyk do promptów subagentów** (`petla`, `petla-noc`) — tam jest gros redundantnych re-readów wielkich plików.
3. **Deleguj pół-mechaniczne-z-osądem do Sonneta** (osobny, pusty cap).
4. Bundla git i nazwane skrypty-ekstraktory (#2–#4) — **opcjonalnie**, łączne netto ~0,2 % capa. Rób tylko jeśli i tak masz je „po drodze"; samodzielnie nie zwracają kosztu budowy.

**Łączny realny potencjał:** otoolowanie komend ≈ **0,5 % capa** (marginalne). Dźwignia indeksu/read-less ≈ **6–11 % capa** (niepewne, w większości = używać istniejącego `tldr` + naprawić prompty subagentów). **Budowa „pętli-narzędzia" się nie zwraca; naprawa nawyku/wiringu — tak.**

---

### Załączniki
- Skrypt: `tools_potential_analyze.py` (deterministyczny, re-run: `python3 tools_potential_analyze.py`)
- Surowy agregat: `/tmp/tp_out.txt` (255 linii — pełne tabele toole/bash/szablony/sekwencje)
- Pomiar uzupełniający: rozmiary gorących plików, użycie `tldr`/`recall` (w treści powyżej)

---

## AKTUALIZACJA 2026-06-14 (pomiar splitu — OBALA szacunek z sekcji „co zrobić")

Zmierzono realny wzorzec dostępu do Code.gs i index.html (`split_measure.py`): **nikt nie czyta tych plików w całości.**

| Plik | Read (7d) | full-read | cat | wzorzec |
|---|---|---|---|---|
| Code.gs (194k tok) | 347 | **0** | 3 | offset/limit, mediana **52 linie** |
| index.html (TimeTrackingApp/122k tok — NIE TheOldWorld/362k; to była kolizja nazw) | 249 | **0** | 0 | offset/limit, mediana **40 linii** |

Dostęp = grep (~1000×) + sekcje ~40–52 linii. Sumaryczna ingestia obu plików w 7d ≈ **403k tok ≈ 0,1 % capa**.

**Wniosek: split tych monolitów daje ~0 dla capa.** Wcześniejszy szacunek „split = 6–11 % capa / najwyższy sufit" był **BRUTTO** (rozmiar × liczba re-readów przy założeniu pełnych odczytów); pomiar pokazał odczyty chirurgiczne (~50 linii), więc **NETTO ≈ 0,1 %** — kolejny przykład pułapki brutto/netto z nagłówka tego raportu (przeszacowanie ~50–100×). Prawdziwy koszt to **częstotliwość nawigacji** (~1600 grep/read na 2 plikach/7d), nie rozmiar — i jest już bliski optymalnego, split tego nie zmniejszy. Split warto rozważać **tylko dla zdrowia kodu**, nie dla capa. Realny, wdrożony lewar capa = zmiana petla (model-per-rola → nocne role mechaniczne na Sonnet + koniec redundantnych re-readów, commit `4aec3bb`).
