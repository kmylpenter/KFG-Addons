# Plan: warm/resident media-player for czytaj read-back (2026-06-15)

**Status:** approach **B implemented (car-gated), deployed & live — awaiting on-car measurement** (2026-06-15).
**Owner:** Kamil + Claude. **Branch when started:** `feat/czytaj-warm-player`.

> See **## Implementation status & how to measure (2026-06-15)** at the bottom for what was
> built, why the gate is "car-connected" instead of the literal "Termux-foreground", and the
> exact in-car measurement + counterfactual that decides whether to ship B or escalate to A+C.

## Why
On-demand VolumeUp read-back is now back to its old ~7-10s on a cache HIT (see memory
`czytaj-readback-design-2026-06-15`). The synth is gone (instant HIT). The remaining latency is
TWO floors, measured on-device 2026-06-15:

1. `_termux_foreground()` rish probe ≈ **3.7s** (lock-screen gate; FIRST press only, then `FG_CACHE` 30s).
2. **`termux-media-player play` start ≈ 3.5s** on Bluetooth — EVERY play. This plan targets THIS one.

`termux-media-player play <wav>` spins up a FRESH Android `MediaPlayer` per call
(`setDataSource` + `prepare` + `start` ≈ 1.6–1.9s) AND, on Bluetooth A2DP, re-establishes the
audio stream if it went idle (≈ 1–2s). A **resident warm player** that stays initialized — and
keeps the BT stream alive — would cut this to ~0.3–0.5s. The latency audit already named this:
*"a resident warm MediaPlayer is the ONLY thing that removes the ~1.6-1.9s play floor."*

Expected gain: **~3.5s → <1s per play** — the single biggest remaining read-back win. Worth it
(user confirmed). Idea (user): spawn it in the background while Termux is active.

## Constraints (hard, this device)
- PRoot Ubuntu on Termux, Android 16, Pixel 9 Pro XL. **No PulseAudio.** Audio MUST reach
  Bluetooth / Android Auto (the car, `myPeugeout`) — so it must go through the **Android media
  path**. `tinyplay`/direct-PCM/AAudio-to-default bypass the BT router → NOT usable (verified).
- czytaj already has Shizuku/`rish` (app_process with shell uid) set up — reuse it, don't add deps.
- Must NOT regress: screen-off playback, pause/scrub (VolumeDown), Voice-Typer interrupt,
  cross-window single-player arbitration (`_reserve_channel`), the lock-screen gate.
- Idle cost must be acceptable on a kiosk tablet (battery + RAM).

## Approaches (survey)
**A. Resident `app_process` MediaPlayer daemon (full solution).**
A small JVM started via `app_process` (the rish/Shizuku mechanism) that:
holds an Android `MediaPlayer` (or `AudioTrack`) warm in an Android context with a `Looper`,
listens on a UNIX socket under the Termux-shared tree, and on `play <wav>` does start (ideally
pre-`prepare`d). Pros: removes the JVM/MediaPlayer cold-start; reaches BT (real Android audio).
Cons: writing a persistent audio service via app_process is non-trivial (Looper, audio focus,
lifecycle, crash-recovery); pre-`prepare` needs knowing the next wav.

**B. Bluetooth A2DP keep-alive (cheap partial win).**
A background loop playing **silence** (tiny silent wav on repeat, or a held silent MediaPlayer)
while Termux is foreground, so the BT A2DP stream never idles → real plays skip the ~1–2s BT
wake. Pros: simple, reuses termux-media-player; likely 1–2s of the 3.5s. Cons: keeps BT busy +
some battery; doesn't remove the MediaPlayer `prepare` cost.

**C. Pre-`prepare` the most-likely-next wav.**
Since the last-5 turns are already cached on disk, a resident player could `setDataSource`+`prepare`
the n=1 (latest) wav in advance, so a VolumeUp `start` is instant. Composes with A. The scrub case
(n=2..5) still pays prepare unless we prepare a small pool.

## Recommended path
1. **SPIKE / measure first** (cheap, decides everything): implement **B** (silence keep-alive while
   Termux foreground) and re-measure `play`→AUDIO-START on BT. If it alone gets us to ~1.5s, ship B
   and stop — the resident-player complexity may not be worth the remaining second.
2. If B is insufficient, build **A + C**: resident app_process audio daemon with a warm,
   pre-`prepare`d player, socket-controlled, spawned by `volume_watcher` while Termux is foreground
   (mirrors the existing keepwarm-daemon pattern). `play_blocking` / `_play_cached_wav` route to the
   daemon's socket instead of forking `termux-media-player`.
3. Keep `termux-media-player` as the FALLBACK when the resident player is down (graceful degradation).

## Acceptance criteria
- Cache-HIT VolumeUp → audible on the car BT in **< 1.5s** (from press, with FG cache warm), vs ~3.5s now.
- A genuine counterfactual: revert the warm player → measured time returns to ~3.5s (proves the gain).
- No regression: screen-off play, pause/scrub, Voice-Typer interrupt, cross-window arbitration,
  lock-screen gate all still pass. Resident player down → falls back to termux-media-player.
- Idle cost documented (battery/RAM with the keep-alive running while Termux foreground).

## Risks / open questions
- Can `app_process` host a long-lived `MediaPlayer` with a `Looper` + audio focus under Shizuku uid?
  (Unknown — the spike must prove it; if not, A is off the table and B is the ceiling.)
- BT A2DP behaviour: does a silent keep-alive actually prevent the wake, or does Android still
  re-route? Measure.
- Audio focus: a resident player must not fight other apps (Spotify/WhatsApp) — honour focus.
- Battery: silence keep-alive while Termux foreground — measure; gate strictly on foreground.

## Pointers
- The play path to reroute: `piper_stream.py` `_play_via_termux_blocking` / `play_blocking` /
  `_play_cached_wav`; the keepwarm pattern to mirror: `volume_watcher.py` `_keep_daemon_warm`.
- Related memory: `czytaj-readback-design-2026-06-15`, `czytaj-playback-floor-structural`,
  `czytaj-native-audio`. Latency audit: `thoughts/shared/petla/czytaj-latency-audit-2026-06-03.md`.

## Implementation status & how to measure (2026-06-15)

**Built: approach B, car-gated.** Added to `volume_watcher.py` (the always-on remote, single
source of the play path's BT context) — deployed to `~/.claude/hooks/czytaj/` and the watcher
restarted (live now, pid changed):
- `_car_connected()` — cached (30s) `rish dumpsys bluetooth_manager | grep -i active:` that
  matches the car name (`CZYTAJ_BT_DEVICE`, default `peugeo`) on a LIVE `Active: <MAC>:` line.
  Verified on-device to discriminate **connected** (matches) from **paired-but-disconnected**
  (no match — the stale `mActiveDevice` field and the bond table are deliberately NOT matched).
  Fails CLOSED → a broken probe never pulses silence into the car.
- `_ensure_silence_wav()` — stages a 60s silent wav under the Termux-shared cache (Android-
  readable; PRoot paths are invisible to `termux-media-player`).
- `_bt_keepalive()` — one tick in the watcher idle loop. Pulses the silence (re-issued every
  ~50s, gapless) to keep the car's A2DP stream warm, and refreshes `PREHEAT_MARKER` so the
  per-read audible wake tone is skipped while warm. Stops the silence when the gate goes false.

**Why car-gated, not the literal "while Termux foreground" (deviation from §Recommended path 1):**
Kamil only uses read-back **in the car**, and gating on foreground alone would (a) on a kiosk
tablet ≈ run continuously, and (b) **yank the car from its own radio to BT-silence** whenever the
tablet sat idle but connected (the A2DP source-switch problem). So the gate is
`car-connected AND (Termux-foreground OR read-back within 90s)` — warm the BT only when actually
in the car AND actively using the tablet to read. Off-car / at home → never runs. This keeps the
interference footprint ≤ today's (the per-read wake tone already pulses the BT) while still
measuring the core hypothesis. Env knobs: `CZYTAJ_BT_KEEPALIVE=0` (off), `CZYTAJ_BT_DEVICE=<name>`.

**Measure in the car (this decides ship-B vs escalate-to-A+C):**
1. Connect the tablet to the Peugeot BT. Focus Termux (so the keep-alive arms + FG cache warms).
   Wait ~10s for the first silence pulse (`grep bt-keepalive ~/.claude/czytaj.log`).
2. Press VolumeUp. Then read the ms-stamped markers:
   `grep -E "keytrigger|read_back|PLAYWAV|AUDIO-START" ~/.claude/czytaj.log | tail`.
   **press→audio = the `AUDIO-START` ts minus the `VOLKEY keytrigger` ts** (both have .mmm).
   Confirm it's a HIT (`ACTION read_back … CACHE-HIT`). Target **< 1.5s** (was ~3.5s).
3. Counterfactual (proves the gain is real): disable it where the respawn will see it — add
   `export CZYTAJ_BT_KEEPALIVE=0` to `~/.claude/hooks/czytaj/czytaj-env.sh` (the env SSOT the
   prompt-hook spawn sources), then restart (`pkill -TERM -f '[v]olume_watcher\.py'`; next prompt
   respawns it). Repeat the press — expect the time to return to ~3.5s. Remove the line to re-enable.
4. Watch for the open risks while measuring: does our silence **interrupt the car radio / your
   music** (audio-focus steal)? battery while connected? If B alone reaches ~1.5s and doesn't
   fight other audio → **ship B, stop.** If not → build **A + C** (resident `app_process`
   MediaPlayer daemon), whose core feasibility is still the unproven spike in §Risks.

**Not measurable off-car (why this is handed back):** audio routes to the car BT; at the tablet
it's silent unless the car is disconnected, so the press→AUDIO-START-on-BT number can only be
read in the car. All off-car checks (compile, detection discrimination, wav staging, single-
instance watcher restart, no key-path regression) pass.

## A+C spike status (2026-06-15 night) — mechanism PROVEN, only BT-routing gate left

Kamil measured B in-car (~2.9–5.4s, down from ~7-10s) and chose to **escalate to A+C**. Spike done on-device
(details + recipe in memory `czytaj-warm-player-spike-2026-06-15`):
- ✅ **on-device dex build** (`javac`+`d8` from PRoot) + **`app_process` runs our code as shell with the live framework**.
- ❌ **`MediaPlayer` is OFF the table** — appops rejects shell uid ("calling package android ≠ uid 2000"), even after
  `AttributionSource`/`ContextImpl` patching. Native player identity stays "android".
- ✅ **`AudioTrack` as shell WORKS** and is the better primitive (raw PCM, no extractor/codec).
- ✅ **A1 daemon PROVEN on the phone speaker:** resident app_process holding a warm AudioTrack, TCP-controlled on
  `127.0.0.1:28771`; from PRoot: ping 2ms, pre-`load` PCM, **`play`→audio in ~5ms** (vs termux-media-player ~2500ms).
  The latency win is real. (`CzytajPlayer.java` in the spike dir; design = `pause()+flush()+play()+write(preloaded PCM)`.)
- ❓ **ONLY remaining gate (car-gated): does the shell `AudioTrack` reach the car A2DP, or only the phone speaker?**
  Couldn't test — the Peugeot BT flapped/disconnected all evening (`A2DP Connected:0`). The plan's core worry.

**Resume path (one command, when connected to MyPeugeot):**
`bash /data/data/com.termux/files/home/.cache/czytaj/spike/route-test.sh` →
`VERDICT: ROUTED type=8` (car ✓ → build A1–A4 as product: daemon + wire `_play_cached_wav` to the socket with
termux-media-player fallback + car-gated keepwarm) **or** `type=2` (speaker ✗ → A is off, **B is the ceiling**).
NOT wired into the live read-back yet (would route to speaker today → would regress the in-car read-back). Approach B stays live.
