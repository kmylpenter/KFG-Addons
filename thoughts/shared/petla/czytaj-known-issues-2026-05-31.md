# czytaj — Known Issues & Handoff (2026-05-31)

Audience: a FRESH session that will run `/petla audit` on the `czytaj` skill.
Context for this doc was written at ~80% context after a long debugging session.

## TL;DR — the meta-cause

The device moved from the **Termux app** to a **native PRoot/Debian** install.
HOME is now `/root`; the Termux user tree is at `/data/data/com.termux/files/home`.
The Android side (termux-media-player, Voice Typer keyboard, Shizuku) lives
OUTSIDE PRoot. Almost every remaining czytaj bug is a consequence of that split:
paths that resolve inside PRoot are invisible to the Android side, and there is
no PulseAudio in the native env. Several fixes already landed; several remain.

## What's the live state RIGHT NOW (important before auditing)

- Installed (live) hooks `~/.claude/hooks/czytaj/` == committed HEAD `a27e132`.
  This state is CONSISTENT and audio is confirmed audible by the user.
- BUT the repo working tree has **uncommitted, INCOMPLETE, BROKEN** edits to
  `addons/czytaj/files/hooks/czytaj/_speak.py` and `piper_stream.py` (my
  partial per-project-flag + voice-typer-path + interrupt work — see Bug 1/2/3).
  They are NOT synced to installed and NOT committed.
  - ⚠️ The per-project half-edit is INCOHERENT: `_speak.py is_active()` now
    checks a per-project flag, but `toggle.sh` still writes the GLOBAL flag.
    If these repo files are synced/committed as-is, **reading mode will never
    activate** (toggle writes global, is_active reads per-project).
  - **RECOMMENDED FIRST STEP for next session:** get a clean baseline before
    auditing — either finish the per-project change across ALL files, or revert:
    `git -C /root/projekty/KFG-Addons checkout -- addons/czytaj/files/hooks/czytaj/_speak.py addons/czytaj/files/hooks/czytaj/piper_stream.py`
    (destructive — discards my uncommitted edits; the diagnosis below preserves the intent).

## Already FIXED + committed this session (do NOT re-fix; verify only)

1. `3883ee4` screen-unlock via `dumpsys power mWakefulness` (was unreliable
   mDreamingLockscreen). Requires Shizuku/ADB; fails open.
2. `7720ba9` X4 cross-window dedup (content-hash ledger
   `~/.claude/czytaj-spoken-ledger.json`, sliding 45s TTL, flock) + spoken
   folder announcement ("KFG-Addons. <tekst>"). Verified by log + concurrency
   test (8 procs → exactly 1 winner).
3. `a84cc5a` piper binary auto-detect across install homes (`$PIPER_HOME` →
   `~/piper-tts` → Termux home). Piper runs fine under PRoot.
4. `2fb285a` audio backend: when no PulseAudio, play via termux-media-player
   (Android MediaPlayer, screen-off capable). `_pulse_available()` picks backend.
5. `a27e132` stage the synthesized wav in a Termux-shared dir
   (`/data/data/com.termux/files/home/.cache/czytaj`) because the Android
   player canNOT read PRoot `/tmp` paths (ENOENT → silence). User CONFIRMED a
   Termux-home wav is audible.

## OPEN BUGS (what to audit + fix)

### BUG A — Voice Typer no longer interrupts / is not detected (HIGH)
- Symptom: user dictating via the Kmylpenter Voice Typer keyboard; TTS started
  talking over the mic. Detection fails entirely.
- Root causes (TWO):
  1. `is_recording()` checks a flag file under
     `~/storage/downloads/Termux-flags/voice-typer-recording.flag`. On PRoot
     `~/storage` does NOT exist → always False. The real Termux-flags dir
     (`/data/data/com.termux/files/home/storage/downloads/Termux-flags/`) is
     currently **EMPTY** — i.e. the current Voice Typer build does NOT appear to
     write any flag at all (confirmed: dir empty during active dictation).
  2. Even fixing the path won't help if no flag is written. Mic-busy detection
     via Shizuku (`is_mic_recording_global`) deliberately EXCLUDES IME/keyboard
     packages (they hold the mic persistently), so it won't catch the keyboard.
- DECISION NEEDED FROM USER: can the Voice Typer keyboard be made to write a
  recording flag again? If yes → trivial + reliable fix (just correct the path
  via `_resolve_voice_typer_flag()`, already drafted in the uncommitted edit).
  If no → must detect the keyboard's mic use specifically; need the keyboard's
  Android package name to special-case it in the Shizuku `dumpsys audio` probe.
- Shizuku IS configured (`~/.claude/czytaj-shizuku.flag` present, `rish` works).

### BUG B — /czytaj is global, not per-project (HIGH)
- Symptom: enabling /czytaj in one project turns TTS on in EVERY open window.
- Cause: single global flag `~/.claude/czytaj.flag`; `is_active()` and
  `toggle.sh` both key off it.
- Intended fix (PARTIALLY drafted, INCOMPLETE — see broken-state warning above):
  per-project flag keyed by `sha1(realpath(project_dir))` under
  `~/.claude/czytaj-flags/<key>.flag`. MUST be applied consistently across:
  - `toggle.sh` (write/remove per-project flag; key from $CLAUDE_PROJECT_DIR
    else $PWD; on OFF only kill piper_server/paplay if `czytaj-flags/` is empty)
  - `_speak.py` `is_active(cwd)` + `_project_flag(cwd)` (DRAFTED)
  - `stop.py` + `pre-tool-use.py` (pass `data.get("cwd","")` into is_active —
    NOT yet done; they still call `is_active()` with no arg)
  - `user-prompt-submit.sh` (replace `[ -f ~/.claude/czytaj.flag ]` with the
    per-project key check)
  - sha1 algorithm MUST match between bash (`printf %s "$(realpath D)" | sha1sum`)
    and python (`hashlib.sha1(realpath.encode())`).
- Decision: new project starts OFF; OFF in one project must NOT silence others.

### BUG C — cross-window queue not honored (playback gets interrupted) (HIGH)
- Symptom: window A is reading; a turn finishes in window B; B's audio
  INTERRUPTS A instead of waiting until the channel is free.
- Cause: on native, all windows share ONE Android MediaPlayer
  (termux-media-player). Starting `play` in B implicitly stops A. The X4 ledger
  prevents the SAME message twice, and `is_self_already_speaking()` was extended
  to check `termux-media-player info` — BUT the non-active pane's guard happens
  before play and there's still a race / the active-vs-background priority isn't
  enforced for the shared single-player model.
- Desired behaviour (from user): active window has priority and may read; a
  background window reads its message only when the channel is FREE (queue),
  never cutting off the active window; each message exactly once; mic-aware.
- Likely needs: a real cross-window playback LOCK/queue (e.g. a lockfile that
  represents "channel busy until ts=end-of-current-wav"), not just a "playing?"
  probe, because the probe has a race and the shared player has no native queue.

### BUG D — speech rate slower + playback feel changed (MEDIUM)
- Symptom: reading tempo is slower than the old Termux-app version.
- Cause: old path streamed raw float32 → paplay with `PIPER_LENGTH_SCALE` and a
  low-latency stream. Native path now does file synth + termux-media-player.
  `synthesize_one_shot` sets `PIPER_LENGTH_SCALE=0.6`; verify it's actually
  applied on the native path and that MediaPlayer isn't resampling/slowing.
  Tune length-scale / sample-rate so native tempo matches the old stream.

## Environment facts (verified this session)
- HOME=/root. node v22, chromium-browser major 148 present.
- piper: `/data/data/com.termux/files/home/piper-tts/piper1-gpl/libpiper/piper`
  (runs under PRoot; needs LD_LIBRARY_PATH=install/lib + ESPEAK_DATA_PATH).
- NO PulseAudio/ALSA/PipeWire in PRoot (`pactl info` → connection refused;
  `/dev/snd` absent). Only audio route = termux-media-player (Termux:API).
- Android player CANNOT read PRoot paths (/tmp, /root) → ENOENT. Must stage
  files under `/data/data/com.termux/files/home/...`.
- Voice Typer Termux-flags dir EMPTY during dictation (no flag written now).
- Shizuku configured; `rish` + `adb` available for dumpsys probes.

## Files (repo ↔ installed; keep in sync)
- repo: `addons/czytaj/files/hooks/czytaj/{_speak.py, piper_stream.py,
  piper_server.py, stop.py, pre-tool-use.py, user-prompt-submit.sh, toggle.sh}`
- installed (live): `~/.claude/hooks/czytaj/` (same names)
- skill md: `addons/czytaj/files/skills/czytaj/SKILL.md`
- After any edit: `cp` repo→installed, `python3 -m py_compile`, `bash -n`,
  `diff -q` identical, commit, do NOT push.

## Testing caveats for the auditor
- The agent shell CANNOT hear audio and the Termux mount is intermittent
  (termux-media-player sometimes "command not found"). `termux-media-player info`
  ("Playing… 0:0X") is the only programmatic "is it playing" signal — but
  confirm real audibility with the USER.
- Bash output in this env BUFFERS/STALLS badly. Do NOT poll with repeated
  echo/`git log` probes (it caused runaway loops this session). If output
  stalls: write results to ONE file, read it ONCE, otherwise proceed.

## Related memory
`~/.claude/projects/-root-projekty-KFG-Addons/memory/`:
`czytaj-native-audio.md`, `czytaj-x4-multiwindow.md`, `petla-skill-ssot.md`,
`env-tool-output-buffering.md`.
