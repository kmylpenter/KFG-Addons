# czytaj — known issues for a fresh audit (2026-06-03)

Pure problem list (no fix history). Each item: observed symptom + where it lives +
impact. Device: Pixel 9 Pro XL, Android 16, PRoot Debian inside Termux, NO PulseAudio,
audio reaches Bluetooth/Android Auto only via `termux-media-player`. Code under
`addons/czytaj/files/hooks/czytaj/`.

## P1 — Read-back is slow (the headline complaint)
- VolumeUp re-read of a recent message: ~6 s press→audio even on a cache HIT; ~11–14 s on a MISS.
- VolumeDown pause/resume: ~3–4 s to take effect.
- "Instant" is the goal; current floor is ~4–6 s. P2–P5 are the components.

## P2 — Synthesis daemon goes COLD in the real multi-process flow
- Synth measured ~7 s COLD vs ~0.8 s warm; in live use it is usually cold.
- A warm daemon can exist yet a fresh synth process does not reuse it → cold every time.
- `server_alive()` (piper_server.py) accepts a daemon that connects but is unresponsive
  → silent cold fallback. Zombie / duplicate `piper-daemon` processes accumulate.
- Where: piper_server.py (`ensure_running`, `run_server`, `get_daemon`, `server_alive`,
  `_spawn_daemon`); piper_stream.py (`synthesize_warm`).

## P3 — Android media-player playback floor ~1.6–2.3 s PER play
- `termux-media-player play` takes ~1.6–2.3 s to begin audible playback, every call
  (one-shot Android MediaPlayer over the Termux:API bridge, cold each time).
- No PulseAudio; tinyplay/direct-PCM bypass the Android router and do NOT reach
  Bluetooth/Android Auto, so they are not usable. No resident/warm player exists.
- This floor is paid on every read-back, pause, resume, and the wake tone.
- Where: piper_stream.py (`_play_via_termux_blocking`, `play_blocking`, `unlock_audio_routing`).

## P4 — Active-window resolution costs ~2 s per press
- Each VolumeUp resolves which window/transcript to read via a live `tmux list-panes`
  subprocess; under load this is ~2 s and runs on (nearly) every press.
- Where: _speak.py (`_resolve_active_transcript`, `_tmux_active_transcript`); called from
  `read_message_back`.

## P5 — The latest message is almost always a cache MISS
- Re-reading the JUST-produced message usually misses the read-back cache → falls to slow synth.
- Contributing: (a) auto-read of that message often does not fire (see P6) so nothing
  caches it; (b) background precache finishes seconds AFTER the message (synth time) and
  loses the race to a quick press; (c) multi-window: read-back resolves the session via
  live tmux, but precache/auto-read key the cache under their OWN session → the wav lands
  in a different cache dir than read-back looks in.
- Where: _speak.py (`read_message_back`, `_readback_cache_get`/`_readback_cache_path`,
  `precache_turn`); precache.py; stop.py.

## P6 — Auto-read is unreliable / frequently silent
- Claude's responses often are NOT read aloud automatically; only the manual volume-key
  read-back reliably produces sound.
- The "is other audio playing / screen unlocked" guard chain is slow (~9 s of serial
  rish/dumpsys probes) and the screen probe flaps under rish-relay contention → false
  SKIP "other-audio" / "locked". The active-session marker can be out of sync with the
  window actually producing output (extra "not-active-session" skips).
- Where: _speak.py (`speak_new_text`/`speak_new` Stop path, `is_other_audio_playing`,
  `is_screen_unlocked`, active-session marker); stop.py.

## P7 — Cross-session synth contention
- With several Claude windows open, every window's Stop hook + precache hits the SINGLE
  serialized synth daemon, starving the focused window's read-back/precache.
- Where: piper_server.py (single `daemon_lock`); stop.py / precache.py fan-out.

## P8 — Daemon process hygiene
- Multiple `piper-daemon` processes can run at once and zombies linger (parented to
  short-lived precache.py); runtime state (socket/pid) can desync from the live process.
- Where: piper_server.py daemon lifecycle.

## Notes for the auditor
- Volume-key DELIVERY itself is fine now (accessibility path is instant, screen-on AND
  screen-off); the slowness is everything AFTER the key (resolve → synth → play).
- ms-precision timing is in `~/.claude/czytaj.log` (markers: keytrigger, read-back,
  SYNTH-DONE, CHANNEL-OK, UNLOCK-DONE, AUDIO-START, AUDIO-END, CACHE-HIT/miss,
  CACHED-READBACK). Useful for measuring any change.
