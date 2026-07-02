# Raport nocny — czytaj — 2026-06-15

> Sesja autonomiczna (jesteś spał). Trzy wątki: (1) spike warm-playera A+C, (2) approach B żyje,
> (3) "petla-noc na czytaj" → że petla-noc jest tylko-GAS, odpaliłem jego przenośny rdzeń
> **`/petla audit`** (czysty raport, ZERO zmian kodu) na ~4600 liniach Pythona/bash czytaj.

---

## ☀️ TL;DR

- **NIC nie zmienione w kodzie** całą noc poza zaplanowanymi (approach B z wczoraj żyje; read-back działa). Audyt = raport, nie mutacje.
- **Audyt czytaj: 1 critical + 17 major** (+ rodziny minorów). Świeży head znalazł realne rzeczy — **w tym 2 błędy w keep-alive, który WCZORAJ wdrożyłem**, oraz **C1, które częściowo tłumaczy latencję** read-backu.
- **Warm-player (A+C): zablokowany na jednym** — werdykt routingu A2DP wymaga połączonego auta (BT rwał się cały wieczór). Wszystko inne udowodnione (ciepły daemon ~5 ms vs ~2500 ms). 1 komenda wznawia.
- Audyt: `thoughts/shared/petla/audit-czytaj-2026-06-15.yaml`. **Naprawa: `/petla solve` w NOWYM oknie** (sam nie ruszam kodu czytaj bez Twojej zgody — brak siatki testów).

---

## 🔴 Audyt czytaj — wyniki (pełny YAML: audit-czytaj-2026-06-15.yaml)

### A. Latencja read-backu (hot-path) — najwięcej do ugrania
- **🔴 C1 (critical):** ścieżka cache-HIT płaci **~0.7 s na słyszalny ton-budzik** (`termux-media-player stop` 0.4s + ton + `sleep` 0.3s) + DRUGI fork `play`, **gdy `PREHEAT_MARKER` jest nieświeży** — czyli **każdy zimny press w domu/na głośniku** (keep-alive odświeża marker tylko w aucie). Prawdziwy wav i tak budzi routing → ton jest czystą latencją. `piper_stream.py:568` → `:166-184`. **Wytnij ton na HIT** = największy pojedynczy zysk, niskie ryzyko. (Łączy się z warm-playerem, który i tak zdejmuje ten ton.)
- **M4:** rish FG-probe (~3.7-8 s) płacony synchronicznie przed audio **co ≥30 s przerwy** (False cache'owane tylko 4 s). `volume_watcher.py:382`. → pre-warm cache z idle-loop.
- **M5:** CAŁY transkrypt jsonl parsowany (`readlines`+`json.loads`) na KAŻDY press przed HIT/MISS, bez memoizacji. `_speak.py:1657/1418`. → memoizuj po mtime / czytaj ogon.
- **M8:** auto-read i precache **dublują syntezę n=1** (ostatniej tury) równolegle na jednym ciepłym daemonie. `stop.py:23`+`precache.py:25`. → precache n=2..N gdy auto-read ON.
- **M9:** precache n=1..5 **seryjnie monopolizuje daemon-lock** — konkuruje z realnym MISS. `precache.py:25`. → n=1..2 eagerly, reszta lazy.
- **M10:** `user-prompt-submit.sh` na KAŻDYM promptcie: **synchroniczny `termux-media-player stop`** (Termux:API round-trip) + 4× `pkill` + zimny import 1690-liniowego `_speak`. → tło (`&`) + mały helper zamiast importu całości.

### B. Wątki / wyścigi / leaki (volume_watcher) — w tym mój wczorajszy keep-alive
- **M1:** `Popen` w `_keep_daemon_warm` (60s) i **moim `_bt_keepalive` (~50s)** nigdy nie reapowane → **zombie ~72/h w aucie**. Brak `SIGCHLD=SIG_IGN`/`wait()`. `volume_watcher.py:661/:66`. → 1 linia `signal(SIGCHLD, SIG_IGN)`.
- **M2:** wyścig compound-RMW na `_readback_n` (debounce jest PER-KOD → VolumeDown+VolumeUp odpalają akcje równolegle) → **scrub na złą wiadomość**. `volume_watcher.py:323/:285`. → lock wokół akcji albo wspólny debounce.
- **M3:** `_last_read_ts` czytane w `_bt_keepalive` (główny wątek) bez synchronizacji vs `_read_back` (wątek dispatch) — może pulsnąć ciszą w aut w momencie startu read-backu. `volume_watcher.py:655`.

### C. 🐛 Bug bramki-dotfile (headline iteracji 2) — M11 + M12
- Sentinel keep-warm `.keepwarm-readback` to **plik-kropka** w `FLAG_DIR`, a trzy bramki shellowe testują pustość przez **`ls -A`** (które LISTUJE kropki). Po pierwszym ON bramka **już nigdy nie jest pusta**:
  - **M11:** teardown w `toggle.sh:20` jest **martwym kodem** — `termux-media-player stop` / pkill / `rm RUN_DIR` / czyszczenie stale-pause-flag **nigdy nie odpalają na OFF**. (Daemon NIE umiera = to akurat zgodne z intencją keep-warm; szkoda = nieczyszczona stała flaga pauzy + martwy kod. To KORYGUJE mój wcześniejszy domysł "daemon może umrzeć" — jest odwrotnie.)
  - **M12:** szybka bramka `|| exit 0` w `stop.sh:8` + `pre-tool-use.sh:8` też martwa → **każdy Stop/PreToolUse na każdym projekcie wchodzi w pythona** nawet gdy nikt nie czyta = regres latencji per-hook.
  - **Fix (jeden, niskie ryzyko):** licz tylko `*.flag` w bramce (`compgen -G "$FLAG_DIR"/*.flag`), nie `ls -A`.

### D. SSOT / DRY — dług (ważne, bo robiłeś refaktor SSOT 2026-06-15)
- **M7:** 3 wartości `CZYTAJ_LOG`/`PAUSE_FLAG`/`KEYPAUSE_STATE` współdzielone py↔bash, konsumowane cross-process, ale **NIE pinowane przez `czytaj_selftest`** → cicha rozjazd przy zmianie nazwy. **6 linii do canary** zamyka dziurę. (Najwyższa dźwignia w tej grupie.)
- **M6+M16:** katalog cache audio + prefiks `/data/data/com.termux/files/...` jako literały poza SSOT (6+ miejsc, 2 bliźniacze resolvery "pierwszy zapisywalny katalog").
- **M13:** 3 listy `pkill` audio triplikowane w 2 językach, bez canary, `toggle.sh` pomija `termux-media-player`.
- **M14:** logika rish/adb zaimplementowana 2×; `volume_watcher` ma własne bare-`rish` **bez fallbacku ADB**.
- **M15:** `READBACK_CACHE_MAX=5` vs literał `"5"` precache — cicho się rozjadą.
- **M17:** katalog Termux-flags zapisany 3 różnymi pisowniami (Download vs downloads).

### E. Security: ✅ CZYSTO / Style: kosmetyka
- **Security — 0 critical/major.** Agent ocenił system jako **dobrze zahartowany**: pliki stanu 0600, daemon waliduje `wav_out` allowlistą, flaga z sdcard ściśle walidowana (key∈{up,down}, mapowana na stałe int — nie trafia do shella), transkrypt do pipera przez **stdin nie argv**, kod pairingu adb sanityzowany. Tylko 2 lokalne minory (m.in. `CZYTAJ_VOLUME_DEVICE` nie-sanityzowane do `rish -c dd` — osiągalne tylko z własnego env, nie z obcego writera).
- **Style — 0 critical/major.** Tylko kosmetyka (3 style logowania, shebang split, `set -e` tylko w setupach). Gęste komentarze F<n> celowo NIE flagowane.

---

## 🎯 Co naprawić NAJPIERW (dźwignia / niskie ryzyko)
1. **C1** — wytnij ton-budzik na cache-HIT (~0.7 s + duplikat-play z każdego zimnego pressu). Największy zysk latencji.
2. **M11/M12** — bramka `*.flag` zamiast `ls -A` (jedna zmiana, odżywia teardown + zdejmuje regres per-hook).
3. **M1** — `signal(SIGCHLD, SIG_IGN)` (1 linia, kończy zombie z keep-alive).
4. **M7** — dopnij 3 wartości do canary `czytaj_selftest` (6 linii, zamyka cichą rozjazd SSOT).
5. **M5 + M8** — memoizacja parsowania transkryptu + precache n≥2 gdy auto-read ON.

---

## 🚗 Warm-player (A+C) — status: zablokowany na aucie
- **UDOWODNIONE:** `app_process` (Shizuku) odpala nasz kod jako shell z żywym frameworkiem; **`AudioTrack` gra jako shell**; **rezydentny daemon `CzytajPlayer` daje audio w ~5 ms** (vs `termux-media-player` ~2500 ms; TCP `127.0.0.1:28771`, pre-load PCM). `MediaPlayer` odpadł (appops).
- **JEDYNE OTWARTE (make-or-break):** czy ten shell-owy `AudioTrack` dociera do **A2DP auta** czy tylko głośnika. Nie do sprawdzenia bez połączonego auta.
- **Wznowienie (1 komenda, gdy w aucie):** `bash /data/data/com.termux/files/home/.cache/czytaj/spike/route-test.sh` → `VERDICT: ROUTED type=8` (budujemy A1-A4) lub `type=2` (A odpada, B sufit).
- Szczegóły: pamięć `czytaj-warm-player-spike-2026-06-15` + `thoughts/shared/plans/czytaj-warm-mediaplayer-2026-06-15.md`.

## Approach B (keep-alive) — żyje
Watcher działa, read-back nietknięty. (Audyt znalazł w nim M1/M3 — do naprawy razem z resztą.)

---

## 📋 Decyzje dla Ciebie
1. **Naprawa audytu:** `/petla solve thoughts/shared/petla/audit-czytaj-2026-06-15.yaml` w **NOWYM oknie**. **Świadomie NIE odpaliłem solve** — czytaj NIE ma siatki testów charakteryzujących, więc nienadzorowane mutacje są ryzykowne. Przejrzyj każdy fix. (Albo: najpierw zbuduj siatkę testów, potem solve za bramką.)
2. **Warm-player:** odpal `route-test.sh` przy następnej jeździe → werdykt zdecyduje A vs B-sufit.
3. **Minory + 2 security-minory:** w YAML jako rodziny — do przejrzenia, większość pewnie wontfix.

## 🔁 Revert
Brak — żadnych zmian kodu tej nocy (audyt to raport). Pliki dodane: `audit-czytaj-2026-06-15.yaml`, ten raport, `spike/` (scaffolding warm-playera, poza repo w `~/.cache`).

## Szczerość pokrycia
- **2 iteracje, status: NIE-skonwergowane (MEDIUM).** Każdy nowy KĄT lensa znajdował nowe realne majory (iter1 hot-path/SSOT=8; iter2 MISS/precache/shell-boundary=10) → audyt **nie jest wyczerpujący**. 3. kąt (klient .html jeśli jest, skrypty install/setup, głębszy error-injection, edge-case daemona) pewnie znalazłby więcej.
- **Dlaczego stop po 2:** świadoma oszczędność capa (Opus współdzielony, tygodniowe limity) na audycie tylko-raportowym. 18 C/M to i tak bardzo solidna, akcjonowalna lista.
- **Security + style** przyjęte jako skonwergowane po iter1 (0 C/M + mocne self-checki) — nie re-uruchamiane.
