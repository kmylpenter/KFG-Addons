# Plan: warm/resident media-player for czytaj read-back (2026-06-15)

**Status:** planned (not started). **Owner:** Kamil + Claude. **Branch when started:** `feat/czytaj-warm-player`.

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
