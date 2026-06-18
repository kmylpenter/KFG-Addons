<!-- SZABLON: petla-noc NIGHT_REPORT. Kolejność sekcji OBOWIĄZKOWA (SKILL.md). -->
# NIGHT_REPORT <data> — petla-noc

Sesja: <start>–<koniec> | Projekty: <n> | Branch: cleanup/<data> | Tryb: <normal|dry-run|RED>

## 🔴 RED / CANARY

<!-- Czerwone testy charakteryzujące — PIERWSZA pozycja, do porannej decyzji.
     Typ: "🔴 SEALED-STABLE" = złamany kontrakt z akceptacji usera (/domknij) — NAJGŁOŚNIEJ;
     "B" = test charakteryzujący z kodu (moduł B). Patrz modules/F.md F1 pkt 3 (prowenancja). -->
| Projekt | Test | Typ | Od kiedy (last green) | Commit-winowajca | Uwagi |
|---|---|---|---|---|---|
| <projekt> | <nazwa> | 🔴 SEALED-STABLE (<feature>, accepted <data>) / B | <data> | <hash/zakres> | <co> |
<!-- brak failów → jedno zdanie: "Wszystkie testy zielone (N testów, M projektów)." -->
RED MODE: <nie | projekt X | GLOBALNY (powód)> — wyłączone moduły: <E, G-impl, I-impl, K, P, R, Z-gen>

<!-- Sealed WIP (z tests-wip/, /domknij) — INFORMACYJNIE, NIGDY nie wywołuje RED (F1b pkt 3).
     Czerwony WIP = feature w rozwoju, NIE regresja. -->
Sealed WIP: <N zielonych, M czerwonych — feature w rozwoju; nie zamyka bramki | brak tests-wip/>

## ☀️ PORANEK — link nocny

<!-- head_restored==false → ⚠ ALARM NA SAMEJ GÓRZE tej sekcji:
     "HEAD chmury = kod nocny! Wykonaj: git checkout <base> && clasp push -f" -->
| Projekt | Link nocny | Końcówka | Wersja | Deploy |
|---|---|---|---|---|
| <projekt> | <night_deployment_url> | **<last3>** | <N> ("petla-noc <data>") | wykonany / POMINIĘTY: <powód> |

Rollback linku: `clasp deploy -i <night_deployment_id> -V <N-1>`
Co klikać: <funkcje/ekrany dotknięte tej nocy przez fixy i kwarantanny — per projekt>
<!-- pierwsza noc: tu ląduje świeżo utworzony link, wyróżnij last3 -->

## ⚠️ DECYZJE DO TWOJEJ AKCEPTACJI

<!-- Wszystko, czego skill nie zrobił z ostrożności. Numerowane, z konkretem "jak zaakceptować". -->
1. [E2/DOUBT] `<funkcja>` w <projekt> — kandydat na kwarantannę, ale <powód wątpliwości>.
   Akceptacja: dopisz `"<funkcja>"` do `.petla-noc/progress.json#quarantine_approved[]`.
2. [H1] Propozycja CONFIG dla <projekt>: <n> hardkodów → klucze <lista>. Akceptacja: powiedz nocy "zrób migrację CONFIG w <projekt>".
3. [I] <n> pustych catch w <projekt> — propozycje per miejsce w tabeli I. <!-- itd. -->
4. [Z] <projekt>: katalog Zoho → +<n> kolumn store (<lista>) dla pól active/high bez kolumny.
   Akceptacja: potwierdź kolumny (addytywny zapis zrobi je noc) lub odrzuć w `zoho-catalog.yaml`.
   1. noc — by włączyć automatyczny zapis: wepnij `__noc_zoho_catalog_sync` PER APKA (Terminator: `if(action===)` w `doPost`; TTA: `case` w routerze `doGet`).
5. [R] <projekt>: GOTOWE do globalnego cutoveru — rozjazdy ~0 przez <N> nocy. Akceptacja: ustaw
   `SOURCE_OF_TRUTH=sheet` w ScriptProperties apki (od teraz tylko arkusz). Pola FORMULA czekające
   na regułę przeliczania: <lista> (bez niej zamarzną po cutoverze).

## ✅ WYKONANE

<!-- Per projekt, per moduł, z hashami commitów. -->
### <projekt>
| Moduł | Wynik | Commity |
|---|---|---|
| F | canary green; diff-audyt: +<n> fresh_debt | — |
| A | mapa: <n> funkcji, <m> dynamicznych, <k> dead_candidates | — |
| B | testy: +<n> plików (green) | — |
| E | fixed: <lista id> / quarantined: <n> funkcji | <hashe> |
| M | mutation: score <przed>→<po>; +<n> testów wzmacniających; B-server +<n>; B-client +<n> | — |
| Z | katalog: <n> pól (active <a>/cand <c>; +unused <u> appendix opc.); store +<k> kol. dokl.; zapis wykonany/POMINIĘTY:<powód> | — |
| R | dual-source: <f> pól uzbrojonych; `SOURCE_OF_TRUTH`=<zoho/sheet>; rozjazdy: <d> | <hashe> |

## 🗃️ MIGRACJA ZOHO→ARKUSZ (moduł Z)

<!-- Stan katalogu pól (zoho-catalog.yaml) — postęp migracji „apka żyje bez Zoho". Akumuluje co noc.
     NIE pojawia się dla projektów bez Zoho (Z = pusty przebieg). -->
| Projekt | Pola active/cand (+unused appx) | Store (cel) | Kolumny są/proponowane | migration_status (cutover/mirrored/proposed/not_started) | Zapis arkusza |
|---|---|---|---|---|---|
| <projekt> | <a>/<c>/<u> | Główna baza danych / DEALS_DATA | <k_exist>/<k_prop> | <x>/<y>/<z>/<w> | wykonany (snapshot __KATALOG_SNAPSHOT) / POMINIĘTY: <powód> |

- Rozjazd ze słownikiem `docs/zoho_*_api_names.md`: <pola w kodzie spoza słownika / błędny typ — lub „brak">.
- Endpoint zapisu (`__noc_zoho_catalog_sync`; Terminator→`doPost` if-chain, TTA→`doGet` case): wpięty / NIEwpięty (DECYZJE — jednorazowe).
- `unused` = OPCJONALNY appendix (różnica słownik∖kod, lub pole znikłe z kodu) — informacyjny, NIE trafia do arkusza.
- ⚠ Katalog ≠ odcięcie Zoho: realny sync rekordów to runtime apki (poza nocą).

## 🔀 PARALLEL-RUN / CUTOVER-READINESS (moduł R)

<!-- Tylko projekty z dual_source: on. Stan dual-source „apka żyje bez Zoho". -->
| Projekt | Pola uzbrojone | `SOURCE_OF_TRUTH` | Rozjazdy (od ost. nocy) | Pola FORMULA czekające | Gotowość cutoveru |
|---|---|---|---|---|---|
| <projekt> | <f> | zoho / sheet | <d> (Telegram: TTA / Terminator=raport) | <lista lub —> | TAK (rozjazdy~0 przez <N> I formula_pending PUSTE) / NIE: <powód / BLOCKER formuł> |

- ⚠ Cutover = JEDEN ręczny flip `SOURCE_OF_TRUTH=sheet` (globalny, w dzień) — patrz DECYZJE. GOTOWOŚĆ =
  rozjazdy~0 **I** `formula_pending` PUSTE; niepuste formula_pending = **BLOCKER** (flip = ciche zamrożenie pól).
- Pola FORMULA/read-only: mirror-only; pełna niezależność wymaga reguły przeliczania w arkuszu.
- Telegram: TYLKO gdy projekt ma bota (dziś TTA); Terminator → raport. `__ROZJAZD_LOG`: FIFO-trim + dedup + kill-switch `divergence_log`.

## 📈 POKRYCIE + 🔓 AUTO-MERGE TIER

<!-- FAZA POKRYCIA (moduł M). mutation score = killed/(killed+survived): czy siatka DYSKRYMINUJE.
     proven = score≥próg I brak survivorów na entry-pointach. Patrz SKILL.md BRAMKA + modules/M.md. -->
### Pokrycie (serwer .gs)
| Projekt | Plik | tests | mutation score | proven | survivory zostały |
|---|---|---|---|---|---|
| <projekt> | <plik.gs> | green | <0.00–1.00> | tak/nie | <n> (L<linia> <op>; …) |

### Pokrycie (klient .html)
| Projekt | Plik | client_tests | uwagi |
|---|---|---|---|
| <projekt> | <plik.html> | green/partial | logika pokryta; glue→smoke; shim-gaps: <API> |

### 🔓 AUTO-MERGE TIER (rekomendacja — noc NIE pushuje do main, wymaganie twarde 5)
<!-- ODPOWIEDŹ na „co mogę scalić bez przeglądu". Decyzję o realnym auto-merge podejmuje
     user; tu jest tylko klasyfikacja ryzyka per commit tej nocy. -->
- **BEZPIECZNE bez przeglądu** (zmiana czysto-logiczna w pliku mutation-proven; smoke zielony
  jeśli był): <hashe + pliki>.
- **ZA CZŁOWIEKIEM** (kwarantanna martwego kodu / plik niepokryty lub mutation NIE-proven /
  dotyka klienta .html / smoke pominięty): <hashe + powód>.
- Smoke (warstwa 3): <wykonany na link nocny: N flow OK | POMINIĘTY: powód, np. brak chromium pod PRoot>.

## ⏭️ POMINIĘTE + DLACZEGO

<!-- Każdy skip/wątpliwość/time-box/degraded — bez wyjątku. -->
- [<moduł>/<projekt>] <co> — <powód: DOUBT(...)|time-box|brak testów|degraded(brak git)>

## ↩️ REVERT

| Commit | Co | Jak cofnąć |
|---|---|---|
| <hash> | quarantine: f1,f2 | `git revert <hash>` (albo przenieś bloki z _deprecated.gs i usuń prefiks) |
| <hash> | fix M3 | `git revert <hash>` |

Całość nocy: repo stoi już na <base_branch> (skill wraca sam na końcu nocy);
cleanup/<data> zostaje do review — odrzucenie całości = po prostu nie merguj
(opcjonalnie `git branch -D cleanup/<data>` po decyzji).

## 📊 STATYSTYKI + PLAN NA NASTĘPNĄ NOC

- Issues: fixed <n> / blocked_no_tests <n> / needs_human_review <n> / open <n>
- Pokrycie testami: <n>/<m> plików green (serwer) + <k> .html (klient) | Kwarantanna: <n> funkcji (łącznie <m>)
- Mutacja: średni score <0.00–1.00>; mutation-proven <n>/<m> plików; survivory zabite <k>, zostały <j>
- Następna noc zaczyna od: <moduł partial / priority_queue top 3 / pliki o najniższym mutation score>
