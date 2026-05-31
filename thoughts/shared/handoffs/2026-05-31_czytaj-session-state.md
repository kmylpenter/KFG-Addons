# czytaj — stan sesji / handoff (2026-05-31, ~92% kontekstu)

Dla ŚWIEŻEJ sesji wznawiającej pracę nad `czytaj` (TTS hands-free na natywnym PRoot/Debian
Android). Model: Opus 4.8. **User pisze i woła po polsku — odpowiadaj po polsku** (kod/commity EN).
Env-gotcha: bash output buforuje (nie polluj pętlami); /tmp PRoot ≠ Android; HOME=/root w PRoot,
strona Android (Voice Typer, Shizuku, termux-media-player) jest POZA PRoot.

## ⏩ UPDATE (sesja 2, 2026-05-31 — kontynuacja): rish NAPRAWIONY + klawisze głośności ZBUDOWANE

**rish z PRoot DZIAŁA** (był OPEN #1). Przyczyna: pod PRoot fake-rootem `[ -w $DEX ]` ZAWSZE zwraca
"zapisywalny" (nawet po `chmod 400`), więc stockowy wrapper rish robił `exit 1` ZANIM doszedł do
app_process. A app_process na tym Androidzie (16/SDK 36) ładuje dex bez problemu — patrzy na realne
bity, nie na fake-root `access()`. Fix w `/root/.shizuku/rish`: fatalny bail zmieniony na ostrzeżenie
(nie exit), 2 diagnostyki na stderr (czyste stdout dla sond). Zweryfikowane: `rish -c id`→uid=2000;
dumpsys power→Awake; dumpsys audio→puste stdout; `ime list -s`→pakiety klawiatur. **Reprodukowalne**:
`setup-shizuku.sh` ma teraz idempotentną łatkę python (po unzip z APK), więc przebudowa env zachowa fix.
- **GOTCHA: SELinux=Enforcing blokuje ZAPIS do /dev/input.** `sendevent` i `input keyevent` NIE
  generują zdarzeń widocznych w getevent (framework injectuje warstwę wyżej). Tylko FIZYCZNE klawisze
  produkują zdarzenia getevent. Odczyt getevent (shell uid) działa — to standard adb.

**Klawisze głośności ZBUDOWANE** (były OPEN #2/#3): nowy `volume_watcher.py` czyta
`rish -c "getevent -l <event0>"` (auto-discovery gpio_keys przez awk-on-android + retry; fallback=all
devices), parsuje naciśnięcia (helper `_press_label`), debounce 0.4s, gating na czytaj-ON, resilient
respawn po restarcie Shizuku, single-instance flock (`czytaj-volume-watcher.lock`).
  - **Volume Down → `stop_now()`** = `termux-media-player stop` + `_kill_audio_chain()`.
  - **Volume Up → `read_last_message()`** = resolve aktywny transkrypt (active-session marker → glob
    `~/.claude/projects/*/<tid>`) → `current_turn_text` → `speak_text_now(priority="active")`. OMIJA
    spoken-ledger, więc re-czyta nawet już-przeczytane.
  Nowe funkcje na końcu `_speak.py`: `stop_now`, `speak_text_now`, `_resolve_active_transcript`,
  `read_last_message`. Wpięte w `toggle.sh`: ON spawnuje watcher (obok piper_server); OFF (ostatni
  projekt) ubija go + `rish -c "pkill -9 getevent"` (Shizuku-side getevent NIE jest dzieckiem klienta).
  - getevent PASSIVE: klawisze NADAL zmieniają głośność (consume wymagałby EVIOCGRAB → zablokowałby
    całe sterowanie głośnością). Gating na czytaj-ON ogranicza to do czasu gdy czytanie aktywne.

**ZWERYFIKOWANE (auto, bez klawisza)**: `_press_label` 10/10 (w tym podchwytliwy release
"KEY_VOLUMEDOWN UP"→None); discovery 4/4→event0; watcher start + flock + getevent-attach;
teardown patterns ubijają watcher+getevent; `read_last` data-path (resolve+extract last msg OK);
py_compile 6 plików + bash -n 6 skryptów; repo==installed (zsync'owane). **Watcher URUCHOMIONY na żywo.**
**NIEZWERYFIKOWANE (wymaga Ciebie — SELinux blokuje syntetyczne zdarzenia)**: fizyczne naciśnięcie.
Ścieżka audio `speak_text_now` = proven-by-reuse (identyczny hand-off do piper_stream jak `_speak_inner`).

### 🔑 TWÓJ TEST KLAWISZY:
1. Tryb czytania ON, watcher działa. Niech Claude coś powie (jest ostatnia wiadomość).
2. **Volume Up** → ma przeczytać OSTATNIĄ wiadomość Clauda od nowa.
3. W trakcie czytania **Volume Down** → ma NATYCHMIAST uciszyć.
4. Diagnoza jeśli nie działa: `grep VOLKEY ~/.claude/czytaj.log | tail` — jeśli BRAK linii
   "VolumeUp/Down" po naciśnięciu → getevent nie dostarcza zdarzeń (buforowanie potoku / złe
   urządzenie); jeśli SĄ linie ale cisza → ścieżka audio. (Jedyne realne ryzyko = buforowanie getevent
   przez potok rish; nie dało się przetestować bez fizycznego klawisza.)

### Wciąż OPEN po sesji 2:
- ^ Fizyczny test klawiszy (jedyna niezweryfikowana rzecz).
- 2-okienny test kolejki na żywo (stary next-step #5, dalej otwarty).
- Commit/push gałęzi `fix/czytaj-audit-2026-05-31` — decyzja usera (NIE pushowane).
- (opcja) Fallback Termux:API notification (Stop/Read-last) — niezbudowany; zbędny jeśli klawisze OK.

---

## CO JUŻ ZROBIONE I DZIAŁA (zweryfikowane na żywo)
- `/petla audit` czytaj → 50 findings w `thoughts/shared/petla/audit-czytaj-2026-05-31.yaml`.
- `/petla solve` → WSZYSTKIE 50 napraw na branchu **`fix/czytaj-audit-2026-05-31`** (14+ commitów)
  i **WDROŻONE** do `~/.claude/hooks/czytaj/` (installed == repo, py_compile/bash -n OK).
- Per-project on/off DZIAŁA (każde okno osobno; sha1 klucza bash==python = 9bef3e9…).
- **BUG A (mic) DZIAŁA end-to-end**: Voice Typer (utrzymywany przez INNEGO Klauda) pisze flagę
  heartbeat na `/storage/emulated/0/Download/Termux-flags/voice-typer-recording.flag`; gdy user
  dyktuje, TTS milknie. Kontrakt: `thoughts/shared/petla/voice-typer-recording-flag-CONTRACT.md`.
- **Tempo (BUG D) DZIAŁA**: piper1-gpl IGNORUJE flagę i env `PIPER_LENGTH_SCALE` — czyta
  `length_scale` z configu głosu. Ustawione 0.6 w `/data/data/com.termux/files/home/piper-tts/voices/pl_PL-gosia-medium.onnx.json`.
  Trwałe w kodzie: `piper_stream._ensure_voice_length_scale()` ustawia je idempotentnie co uruchomienie
  (default z env `PIPER_LENGTH_SCALE`, fallback 0.6) → przetrwa re-download głosu. (User chce 0.6.)
- **Kolejka między oknami WDROŻONA** (na życzenie usera): w JEDNYM oknie „najnowszy wygrywa"
  (single-player play zastępuje); MIĘDZY oknami KOLEJKA — `piper_stream._reserve_channel()` czeka aż
  inne okno skończy (cap 45s, fail-open → gra). Usunięty globalny `_kill_audio_chain` z `_speak_inner`
  (ciął inne okna). Flush nowej tury nadal w UPS hooku. — **wymaga jeszcze testu na 2 oknach na żywo.**

## DECYZJE (ta sesja)
- D-BASELINE: finish-forward (zachowane dobre patche z half-editu), nie blind-revert.
- D-BUGA: keyboard pisze flagę (NIE ścieżka IME-allowlist — ryzyko permanentnego wyciszenia).
- D-PAUSE: pauza zostaje GLOBALNA (jeden fizyczny głośnik).
- W oknie: latest-wins. Między oknami: kolejka. Tempo: globalne (jeden config głosu).
- User preferuje odpowiedzi po polsku (memory: prefer-polish-responses).

## OTWARTE — TU JESTEŚMY (priorytet do dalszej pracy)
### 1. (W TOKU) Shizuku/rish ZEPSUTY z wnętrza PRoot — NAPRAWIĆ
- **WAŻNE rozróżnienie:** Shizuku-USŁUGA działa (utrzymuje klawiaturę Voice Typer + pasek przycisków
  overlay w Termuksie — user to potwierdza). Problem jest tylko z **rish** (CLI powłoka shell-uid przez
  Shizuku, używana przez czytaj do `dumpsys` — detekcja ekranu/mikrofonu).
- **Objaw:** `rish -c id` z PRoot → „On Android 14+, app_process cannot load writable dex. Cannot remove
  the write permission of …rish_shizuku.dex." Android 14+ wymaga NIE-zapisywalnego dex; `chmod 400` NIE
  bierze na tych systemach plików (ACL `+`: zarówno Termux `/data/data/...` jak i PRoot `/root`).
- **Dwa nakładające się problemy:** (a) wrapper `rish` robi `exec "$HOME/.shizuku/rish"` → z PRoot HOME=/root
  → szukał /root/.shizuku (nie było); rish faktycznie leży w `/data/data/com.termux/files/home/.shizuku/`.
  (b) dex `rish_shizuku.dex` jest `-rw-------` i nie da się odebrać prawa zapisu na tym FS.
- **Co próbowałem:** skopiowałem rish do `/root/.shizuku/` (rozwiązuje (a)), ale (b) zostaje — chmod 400
  nie bierze nawet w /root (ACL). rish podpowiada: skopiować dex do „/data/data/<package>" (prawdziwy
  prywatny katalog apki) gdzie da się odebrać write, albo do `/data/local/tmp` (shell-uid może tam pisać+chmod).
- **Skutek uboczny:** detekcje screen-unlock (dumpsys power mWakefulness) i mic-przez-Shizuku
  (`is_mic_recording_global`) z hooków PRoot CICHO fail-open. Działa tylko mic-przez-flagę (keyboard).
  `czytaj-shizuku.flag` = "ready" więc `_speak.py:_shell_cmd_prefix` zwraca ["rish","-c"] → rish pada → fail-open.
- **Kierunek naprawy do zbadania:** umieścić dex tam, gdzie app_process zaakceptuje non-writable
  (np. `/data/local/tmp/` — shell-uid pisze, ale chicken-egg bo trzeba shell; albo prawdziwy app-private dir).
  Możliwe że trzeba użyć ADB-path (setup-adb-pairing) zamiast Shizuku, albo zaktualizować rish/Shizuku.
  User MÓWI „napraw Shizuku" — to jest następny task.

### 2. Funkcja: klawisze głośności jako sterowanie (user bardzo chce — „mega funkcjonalność")
- Pomysł usera: gdy TTS aktywny — **Volume Down = STOP czytania**, **Volume Up = przeczytaj OSTATNIĄ
  wiadomość Clauda**. Klawisze fizyczne działają nawet gdy jestem w trakcie tury.
- Termux przechwytuje klawisze głośności jako modyfikatory → nie da się ich podpiąć pod skrypt w samym
  Termuksie. **Rozwiązanie = Shizuku `getevent`** (czyta surowe zdarzenia kernela globalnie, niezależnie
  od przechwycenia) → watcher-daemon filtruje KEY_VOLUMEDOWN(114)/VOLUMEUP(115) → odpala akcje.
  **Blokuje to (1): rish musi najpierw działać.** Gating: reagować tylko gdy czytaj ON (inaczej nie
  porywać głośności). Daemon: start + restart po Shizuku/reboot. Debounce key-down.

### 3. Akcje (łatwe, niezależne od triggera) — do zbudowania
- „STOP czytania teraz": `termux-media-player stop` (Termux:API, natychmiast) + ew. globalna flaga mute.
- „Przeczytaj ostatnią": czytaj zna aktywną sesję (ACTIVE_SESSION marker) → wyciągnąć ostatnią
  wiadomość asystenta z transkryptu → zsyntetyzować. Buildable.
- Trigger do wyboru: (a) klawisze głośności przez getevent [potrzeba rish], (b) **powiadomienie Termux:API
  z 2 przyciskami Stop + Przeczytaj-ostatnią** [bez Shizuku, pewne], (c) widget Termux:Widget [osobna apka].

### 4. Instant on/off toggle (problem: nie da się wyłączyć w trakcie mojej tury)
- Claude kolejkuje wiadomości usera w trakcie generowania → in-band toggle niemożliwy mid-turn.
- „FileChanged hook" zasugerowany przez agenta — ODRZUCONY (nie ma go w settings ani standardowych zdarzeniach).
- Rozwiązanie = poza Claude (jak w pkt 2/3: getevent przez Shizuku, albo przycisk w powiadomieniu).

## KLUCZOWE ŚCIEŻKI
- Hooki repo: `addons/czytaj/files/hooks/czytaj/{_speak.py,piper_stream.py,piper_server.py,stop.py,
  pre-tool-use.py,*.sh}` · installed (żywe): `~/.claude/hooks/czytaj/`.
- Audit: `thoughts/shared/petla/audit-czytaj-2026-05-31.yaml` (solve_directives + user_decisions z answerami).
- Deploy/test guide: `thoughts/shared/petla/czytaj-DEPLOY-AND-VERIFY.md`.
- Kontrakt klawiatury: `thoughts/shared/petla/voice-typer-recording-flag-CONTRACT.md`.
- Głos config: `/data/data/com.termux/files/home/piper-tts/voices/pl_PL-gosia-medium.onnx.json` (length_scale=0.6).
- rish: binarka w `/data/data/com.termux/files/home/.shizuku/` (skopiowana też do `/root/.shizuku/`, ale dex-issue zostaje).
- Branch: `fix/czytaj-audit-2026-05-31` (NIE pushowany; per-group commity; rollback do a27e132-era backupu w `~/.claude/hooks/czytaj.bak-*`).

## NASTĘPNE KROKI (kolejność)
1. **Napraw rish z PRoot** (Android-14 writable-dex): umieścić dex tam gdzie app_process przyjmie
   non-writable (próby: `/data/local/tmp`, prawdziwy app-private). Cel: `rish -c id` → uid=2000 z PRoot.
   To odblokowuje getevent + przywraca detekcję ekranu/mic-Shizuku.
2. **Zbuduj watcher getevent** (jeśli rish OK): VolumeDown→stop, VolumeUp→przeczytaj-ostatnią; gating na czytaj ON; daemon.
3. **Zbuduj akcję „przeczytaj ostatnią"** (skrypt korzystający z ACTIVE_SESSION + ostatniej wiadomości).
4. **Fallback bez Shizuku**: powiadomienie Termux:API z przyciskami Stop + Przeczytaj-ostatnią.
5. **Dokończ test na żywo**: kolejka między 2 oknami (active preempts? background czeka?), per_project_min_check z deploy-guide.
6. Po wszystkim: rozważyć commit „cross-window queue + durable tempo" jest już na branchu; ew. push/PR gdy user zdecyduje.

## JAK WZNOWIĆ
Przeczytaj ten plik + `audit-czytaj-2026-05-31.yaml` (solve_directives) + `czytaj-DEPLOY-AND-VERIFY.md`.
Memory: czytaj-audit-2026-05-31, prefer-polish-responses, czytaj-native-audio, env-tool-output-buffering.
Tryb czytania jest WŁĄCZONY dla projektu KFG-Addons (flaga w ~/.claude/czytaj-flags/9bef3e9….flag).
