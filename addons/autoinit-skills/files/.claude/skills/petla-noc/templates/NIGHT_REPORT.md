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
RED MODE: <nie | projekt X | GLOBALNY (powód)> — wyłączone moduły: <E, G-impl, I-impl, K, P>

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

## ✅ WYKONANE

<!-- Per projekt, per moduł, z hashami commitów. -->
### <projekt>
| Moduł | Wynik | Commity |
|---|---|---|
| F | canary green; diff-audyt: +<n> fresh_debt | — |
| A | mapa: <n> funkcji, <m> dynamicznych, <k> dead_candidates | — |
| B | testy: +<n> plików (green) | — |
| E | fixed: <lista id> / quarantined: <n> funkcji | <hashe> |

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
- Pokrycie testami: <n>/<m> plików green | Kwarantanna: <n> funkcji (łącznie <m>)
- Następna noc zaczyna od: <moduł partial / priority_queue top 3>
