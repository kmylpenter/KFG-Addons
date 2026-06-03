# czytaj read-back latency audit (4 parallel Opus agents, 2026-06-03)

Measured on-device (Pixel 9 Pro XL, PRoot Debian in Termux, NO PulseAudio, audio via
termux-media-player → Android MediaPlayer → Bluetooth/Android Auto). Press→audio on a
cache-MISS ≈ 6.5s, split: ~0.4s pre-synth + ~2.3–3.3s synth + ~0.7s unlock-tone + ~1.6–1.9s
media-player start. Key delivery itself is instant (~11ms).

## THE headline fix (Agent 3, Finding 1+4) — biggest win, makes re-read an instant HIT
Auto-read ALREADY synthesizes each message to a real wav (`piper_stream.py:661-674`,
`synthesize_warm` — the SAME function precache uses) then **DELETES it** (`piper_stream.py:679`
`wav.unlink()`). That wav is exactly what read-back wants and it's thrown away.
- Fix: `os.replace()` the played wav into the read-back cache dir instead of deleting →
  re-reading the last message = instant cache HIT, ZERO synth. Scratch dir and cache base are
  on the SAME filesystem (verified st_dev) → atomic zero-copy rename.
- Cache key = `sha1(raw turns[-n])`, identical in precache + read (`_speak.py:1470`,`1543`,`1643`) — they match.
- CAVEAT (Finding 4, CRITICAL): the cache DIR is `base/<session-basename>/`. Read-back resolves
  the session via LIVE TMUX active window (`_resolve_active_transcript` step 0,
  `_tmux_active_transcript` `_speak.py:1306/1350`); precache uses the Stop-hook's OWN transcript;
  the active-session marker is a THIRD value. In multi-window use these DIVERGE → the saved wav
  lands in a different dir than read-back looks in → still a miss. So the wav MUST be saved under
  the dir `_resolve_active_transcript()` will resolve to (pass the resolved session through).
- Also a latest-turn GROWTH race: a turn emits several assistant messages over seconds; precache
  caches an early `turns[-1]` that's stale by press time. Reusing the played wav sidesteps this.

## Auto-read is BROKEN/flaky — prerequisite for the headline fix (Agent 3, Finding 2)
Auto-read produces no audio often (logs: SKIP other-audio ×460, but it DID speak ×345 → flaky,
not dead). Root cause: `is_other_audio_playing` guard chain (`_speak.py:1017`, chain `:525-561`)
runs ~9.7s of SERIAL rish/dumpsys probes; the screen probe `is_screen_unlocked` (`_speak.py:349`)
FLAPS under rish relay contention (volume_watcher + many Stop hooks saturate the single
app_process relay) → writes `screen.cache=0` (locked) while the device is actually Awake →
auto-read SKIPs "other-audio" for the 5s TTL. Fixes (low risk): only write `0` on a CONFIDENT
Asleep/Dozing/Dreaming token (treat torn/empty dumpsys as Awake = fail-open); lengthen
SCREEN_CACHE_TTL_S (currently 5s); short-circuit the foreign-audio chain when active+kill_previous;
collapse the 4 probes into one rish round-trip. Also: active-session marker (`50329073`) out of
sync with the producing window (`2f623c9d`) and tmux-active (`0c9abe57`) → not-active-session ×37.

## Synth daemon never actually warm (Agent 1) — when synth IS needed, make it ~1s not 3.3s
0 `READY` markers in 11k log lines; every SYNTH-DONE ≥2.29s. Warm floor on this device ≈1.0–1.4s
(measured live), cold ≈3.3s. Idle daemon = **0% CPU, ~111MB RAM** (sleeps) → keeping it warm is
FREE battery-wise. Cuts:
1. **server_alive() must PING** (`{"ping":1}`→`{"ok":true}`, ~0.3s timeout), not just check the
   socket file/connect — a dead daemon behind a live/stale socket currently passes the check →
   silent cold fallback every call. `piper_server.py:77,94-117,327`. Removes the cold-fallback class. LOW.
2. **Disable idle timeout while a flag exists**: `sock.settimeout(None)` when `FLAG_DIR` non-empty,
   re-check each accept loop to self-reap when reading toggles off. `piper_server.py:320,376-381`.
   Kills the 30-min cold cliff. LOW.
3. Pin RUN_DIR to a fixed absolute path (now `XDG_RUNTIME_DIR or TMPDIR or /tmp` → empty XDG →
   `/tmp/claude-0/piper-server`, but a stale `/tmp/piper-server` from unset-TMPDIR sessions causes
   split daemons + zombies). `piper_server.py:55` (grep toggle.sh/install.sh to match). MED.
4. Vectorize float32→int16 clamp with numpy (guarded). `piper_stream.py:304-308`. ~50-150ms. LOW.
- Double-fork detaches correctly (verified) — NOT the persistence bug. pkill patterns correctly
  exclude piper_server/piper-daemon — do NOT touch.

## Pre-synth ~0.3-0.5s gap = uncached tmux subprocess every press (Agent 4) — THE quick win
`_resolve_active_transcript` step 0 runs `_tmux_active_transcript()` = blocking `tmux list-panes`
subprocess (`_speak.py:1306,1331-1335`, timeout 4) on EVERY press, NO cache. ~0.2-0.4s = the
measured pre-synth gap.
1. **Cache `_tmux_active_transcript` ~1-2s** (active window can't change between rapid presses).
   ~250-400ms/press. LOW. ← single highest-value quick win.
2. Resolve transcript ONCE per scrub burst (reuse in volume_watcher `_read_back`). LOW.
3. Bound `_turn_texts()` to the tail (~last 50 turns); it `readlines()` the whole .jsonl each press
   (now 3.55MB/142 turns ≈23ms, grows linearly). `_speak.py:1395`. ~15-80ms, future-proof. LOW-MED.
- Flag press path is otherwise pure file reads (trusted_fg=True skips `_termux_foreground` rish). ✓
- **Logs: clearing czytaj.log gains ~0ms** — append-only, NOTHING reads it (verified). `rm` is safe
  for disk hygiene only, not speed. (711KB/11k lines now.)

## Playback ~1.6-1.9s media-player start = HARD FLOOR (Agent 2)
No faster BT-capable route than termux-media-player without PulseAudio (tinyplay/direct-PCM bypass
the Android router → won't reach BT/Android Auto). The ~1.6-1.9s is intrinsic MediaPlayer
setDataSource+prepare cold-start, paid per invocation. Cuts that don't need a warm-player redesign:
1. Refresh PREHEAT_MARKER on every successful message play (`piper_stream.py:370`) so the wake tone
   stays a no-op across consecutive reads. ~700ms. LOW.
2. Pre-pend the wake tone INTO the cached wav at build time → ONE `play` (tone+message) instead of
   two MediaPlayer starts. ~1.6-1.9s when a tone is needed. LOW-MED.
3. Memoize `_pulse_available()` (module-level; immutable on this device; called 2-3×). ~50-300ms. LOW.
4. (flag, MED) volume_watcher plays the cache-hit wav IN-PROCESS instead of forking a fresh
   python3 piper_stream (~250-300ms interpreter spawn). Needs sharing the pause-aware poll logic.
5. (flag, HIGH effort) a resident warm MediaPlayer is the ONLY thing that removes the ~1.6-1.9s floor.

## Recommended order (each independently shippable)
1. Fix auto-read flapping (screen probe fail-open + TTL) — Agent 3 Finding 2. Prereq for #2.
2. Save the auto-read's played wav into the read-back cache under the RESOLVED session dir —
   Agent 3 Finding 1+4. → re-read last message = instant HIT (kills synth for the common case).
3. Cache `_tmux_active_transcript` ~1-2s — Agent 4. → kills the ~0.4s pre-synth gap.
4. Keep daemon warm (idle off while flag) + server_alive PING — Agent 1. → synth ~1s not 3.3s when needed.
5. Playback: refresh PREHEAT_MARKER + memoize pulse + (optional) fuse tone into wav — Agent 2.
   The ~1.6s MediaPlayer floor remains unless a warm-player is built.
Logs: clearing = no speed gain (hygiene only).
