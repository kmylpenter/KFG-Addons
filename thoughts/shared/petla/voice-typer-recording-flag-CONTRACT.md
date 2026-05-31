# Voice Typer ↔ czytaj — recording-flag integration contract

**Dla użytkownika (PL):** to jest gotowa instrukcja do przekazania temu Klodowi, który
utrzymuje aplikację **Voice Typer** (klawiaturę dyktowania). Opisuje DOKŁADNIE co
klawiatura ma robić, żeby czytaj (TTS) przestawał mówić, gdy zaczynasz dyktować.
Strona czytaj jest już gotowa/poprawiana po mojej stronie — brakuje tylko tego, żeby
klawiatura *zapisywała flagę*. Przekaż całą sekcję „SPEC" poniżej.

---

## SPEC — for the Claude maintaining the Voice Typer keyboard app

### Goal
`czytaj` is a hands-free TTS mode that reads Claude's replies aloud on this Android
tablet. It must **stop talking the instant the user starts dictating** (and not start
talking while the mic is open). Detection is done via a single **flag file on shared
storage**: the Voice Typer keyboard writes the flag while its microphone/dictation is
active, and removes it when dictation stops. That is the *only* thing the keyboard
needs to do for this integration.

### The rendezvous file (EXACT — do not change the path)
```
/storage/emulated/0/Download/Termux-flags/voice-typer-recording.flag
```
- Equivalent Android paths: `/sdcard/Download/Termux-flags/voice-typer-recording.flag`.
- The directory `/storage/emulated/0/Download/Termux-flags/` **already exists** and is
  group-writable. If it is ever missing, create it (`mkdirs`).
- Do **NOT** write to any `/data/data/com.termux/...` path — that is Termux's private
  sandbox and the keyboard cannot see it. Shared storage (`/sdcard/Download/...`) is the
  only place both apps can reach; the czytaj side reads it through a Termux symlink.
- The keyboard app needs storage-write access to the Downloads collection
  (`WRITE_EXTERNAL_STORAGE` on legacy targets, or `MANAGE_EXTERNAL_STORAGE` / a
  `MediaStore.Downloads` write on Android 11+). Use whatever your app already uses to
  write to `/sdcard/Download`.

### Detection semantics
- **File present → "user is dictating" → czytaj stays silent / stops mid-sentence.**
- **File absent → czytaj may speak.**

### Required lifecycle (the contract)
1. **On dictation START** (mic opened / speech recognition session begins — ideally in
   the same callback where you start the recognizer, *before* the first audio frame):
   **create/overwrite** the flag file.
2. **On dictation STOP** (mic released, recognizer ended, result committed/cancelled):
   **delete** the flag file.
3. **Also delete the flag on every "input session ends / keyboard goes away" path**, so a
   stuck flag never mutes TTS forever:
   - `InputMethodService.onFinishInput()` / `onFinishInputView(finishingInput=true)`
   - `onWindowHidden()` / keyboard dismissed
   - `onDestroy()`
4. **On keyboard init** (`onCreate()` / first `onStartInput`): **delete any pre-existing
   flag** — this clears a stale flag left by a previous crash so TTS is never permanently
   muted after a force-stop.

### RECOMMENDED robustness: heartbeat + timestamp (crash-safe, self-healing)
Plain create/delete is enough for normal use, but a hard crash mid-dictation could leave
a stale flag (TTS muted until the keyboard is reopened). To make it self-healing:

- While the mic is open, **write the current Unix epoch time (integer seconds, ASCII
  decimal) as the file's contents, and rewrite it every ≤ 1 second** (a lightweight
  heartbeat — a `Handler.postDelayed` loop or the recognizer's partial-result callback is
  fine).
- Still **delete** the file on stop (so a normal stop is instant, not waiting for
  staleness).
- The czytaj side will then treat the flag as "recording" only if its timestamp is within
  the last few seconds; a crashed keyboard's timestamp goes stale and TTS resumes
  automatically. **(This staleness check is implemented on the czytaj side — you only need
  to write/refresh the timestamp.)**

Format: a single decimal integer, e.g. `1717182000`. Trailing newline optional. Write
atomically if convenient (write to a temp file + rename), but a plain overwrite of this
tiny file is acceptable.

### Timing
- czytaj waits up to **0.6 s** (polling every 0.05 s) before it starts speaking, and polls
  again **every ~0.3 s while it is already playing**. So if the flag appears within
  ~100 ms of the mic opening, czytaj will not talk over you and will cut off within a
  fraction of a second if you interrupt it. Create the flag as early as possible in the
  mic-open path.

### Minimal Android pseudocode (adapt to your app)
```kotlin
private val FLAG = File("/storage/emulated/0/Download/Termux-flags/voice-typer-recording.flag")
private val hb = Handler(Looper.getMainLooper())
private val beat = object : Runnable {
    override fun run() {
        FLAG.parentFile?.mkdirs()
        FLAG.writeText((System.currentTimeMillis() / 1000).toString())  // heartbeat
        hb.postDelayed(this, 1000)
    }
}
fun onDictationStart() { hb.post(beat) }            // create + keep refreshing
fun onDictationStop()  { hb.removeCallbacks(beat); FLAG.delete() }
// also call onDictationStop() from onFinishInput()/onWindowHidden()/onDestroy()
// and FLAG.delete() once in onCreate() to clear a stale flag from a prior crash
```

### How to verify it works (no czytaj code needed to test the keyboard side)
1. With czytaj reading something aloud, start dictation on the keyboard.
2. Confirm the file appears:
   `adb shell ls -l /sdcard/Download/Termux-flags/voice-typer-recording.flag`
   (or check from Termux: `ls -l ~/storage/downloads/Termux-flags/`).
3. TTS should go silent within ~0.3 s.
4. Stop dictation → confirm the file is **deleted** → TTS may speak again on the next turn.
5. Force-stop the keyboard mid-dictation → with the heartbeat, the flag should be ignored
   by czytaj after a few seconds (stale) and removed; without the heartbeat, reopen the
   keyboard once to clear it (step 4 in the lifecycle).

### Out of scope for the keyboard
- The keyboard does **not** call termux-media-player, does not touch piper, does not read
  any czytaj state. Its entire job is: **write the flag while dictating, delete it when
  done.** Everything else is handled on the czytaj side.

---

## czytaj-side counterpart (handled in this repo — for reference, not for the keyboard)
- `_resolve_voice_typer_flag()` already resolves to
  `/data/data/com.termux/files/home/storage/downloads/Termux-flags/voice-typer-recording.flag`
  which is the symlinked view of the shared-storage path above (verified 2026-05-31).
- If the heartbeat/timestamp option is adopted, `is_recording()` (currently a bare
  `os.path.isfile`) will be changed to: file exists AND `now - int(content) < STALE_S`
  (≈3–4 s), else not-recording (and unlink the stale flag). This is audit finding **F10**
  (BUG A) + the `_resolve_voice_typer_flag` duplication note **F27** (the resolver lives in
  both `_speak.py` and `piper_stream.py` — both get the same change).
