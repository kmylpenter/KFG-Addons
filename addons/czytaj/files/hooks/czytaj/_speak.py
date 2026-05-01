"""Shared speak logic for czytaj hooks.

State file tracks the last spoken assistant message uuid and the exact text
already spoken from it, so successive hooks (PreToolUse → ... → Stop) only
read the new suffix instead of repeating earlier content.
"""
import errno
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import time

FLAG_FILE = os.path.expanduser("~/.claude/czytaj.flag")
STATE_FILE = os.path.expanduser("~/.claude/czytaj-state.json")
SPEAK_LOCK = os.path.expanduser("~/.claude/czytaj-speak.lock")
LOG_FILE = os.path.expanduser("~/.claude/czytaj.log")
PAUSE_FLAG = os.path.expanduser("~/.claude/czytaj-pause.flag")
PAUSE_DEFAULT_S = 60.0
ADB_FLAG = os.path.expanduser("~/.claude/czytaj-adb.flag")
SCREEN_CACHE = os.path.expanduser("~/.claude/czytaj-screen.cache")
SCREEN_CACHE_TTL_S = 2.0


def _log(*parts: object) -> None:
    """Append timestamped event line to ~/.claude/czytaj.log. Never raises."""
    try:
        with open(LOG_FILE, "a") as f:
            ts = time.strftime("%H:%M:%S")
            f.write(f"{ts} pid={os.getpid()} {' '.join(str(p) for p in parts)}\n")
    except OSError:
        pass
SILENT_WAV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "silent.wav")
PIPER_STREAM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "piper_stream.py")
PIPER_BIN = os.path.expanduser("~/piper-tts/piper1-gpl/libpiper/piper")
VOICE_TYPER_FLAG = os.path.expanduser(
    "~/storage/downloads/Termux-flags/voice-typer-recording.flag"
)
MAX_SPOKEN_TEXT_BYTES = 16384


def preheat_audio() -> None:
    """No-op: paplay (PulseAudio) handles its own routing reliably on Termux,
    and the old termux-media-player based preheat blocked the hook timeout
    chain. Audio focus issues during phone calls are now handled by Android."""
    return


def is_active() -> bool:
    return os.path.isfile(FLAG_FILE)


def is_recording() -> bool:
    return os.path.isfile(VOICE_TYPER_FLAG)


def is_in_call() -> bool:
    """Termux can't read call_state without root — termux-telephony-deviceinfo
    omits it, dumpsys is blocked. Stub returns False; we rely on Android's
    own audio focus management to mute paplay during calls."""
    return False


def is_paused_by_user() -> bool:
    """User-toggled mute flag — the only mechanism that reliably suppresses
    TTS on Android 16. The flag's content is the epoch second at which the
    pause expires (empty = indefinite). Set via the /pauza command or
    `touch ~/.claude/czytaj-pause.flag`."""
    try:
        with open(PAUSE_FLAG, "r") as f:
            content = f.read().strip()
    except OSError:
        return False
    if not content:
        return True
    try:
        expires_at = float(content)
    except ValueError:
        return True
    if time.time() >= expires_at:
        try:
            os.unlink(PAUSE_FLAG)
        except OSError:
            pass
        return False
    return True


def is_device_silenced() -> bool:
    """Skip TTS when the user has muted the music stream specifically.
    Piper plays through the music stream; if music==0 the user wants
    silence regardless of why. Notification stream is intentionally NOT
    consulted — Do-Not-Disturb mode often forces notification=0 while
    media playback is still desired. termux-volume returns a JSON array
    of {stream, volume, max_volume}. ~150 ms call, well under hook
    budget. Returns False on any failure (don't suppress TTS just
    because the probe broke)."""
    try:
        r = subprocess.run(
            ["termux-volume"],
            capture_output=True, text=True, timeout=1.5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False
    if r.returncode != 0:
        return False
    try:
        data = json.loads(r.stdout)
    except (json.JSONDecodeError, ValueError):
        return False
    vols = {item.get("stream"): item.get("volume", -1)
            for item in data if isinstance(item, dict)}
    return vols.get("music", 1) == 0


def _read_screen_cache() -> bool | None:
    """Return cached unlock state if cache file is fresh, else None."""
    try:
        st = os.stat(SCREEN_CACHE)
    except OSError:
        return None
    if time.time() - st.st_mtime > SCREEN_CACHE_TTL_S:
        return None
    try:
        with open(SCREEN_CACHE) as f:
            v = f.read().strip()
    except OSError:
        return None
    return v == "1"


def _write_screen_cache(unlocked: bool) -> None:
    try:
        with open(SCREEN_CACHE, "w") as f:
            f.write("1" if unlocked else "0")
        os.chmod(SCREEN_CACHE, 0o600)
    except OSError:
        pass


def is_screen_unlocked() -> bool:
    """True iff the phone screen is on AND not on the lock screen.

    Mechanism: ADB-over-localhost (configured one-time via
    setup-adb-pairing.sh, sentinel at ~/.claude/czytaj-adb.flag). If the
    sentinel is absent, returns True — feature is opt-in, missing setup
    must NOT silence TTS. If adb fails for any reason (daemon dead, paplay
    timing out, dumpsys denied), also returns True (fail open).

    Cached for 2s to avoid spawning an adb shell on every PreToolUse hook
    fire when /petla pumps several tools per turn."""
    if not os.path.isfile(ADB_FLAG):
        return True
    cached = _read_screen_cache()
    if cached is not None:
        return cached
    try:
        r = subprocess.run(
            ["adb", "shell", "dumpsys", "window"],
            capture_output=True, text=True, timeout=2.0,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        _write_screen_cache(True)
        return True
    if r.returncode != 0:
        _write_screen_cache(True)
        return True
    out = r.stdout
    locked_signals = (
        "mDreamingLockscreen=true",
        "mShowingDream=true",
        "mShowingLockscreen=true",
        "mAwake=false",
        "mScreenOn=false",
    )
    for sig in locked_signals:
        if sig in out:
            _write_screen_cache(False)
            return False
    _write_screen_cache(True)
    return True


def is_self_already_speaking() -> bool:
    """Already streaming TTS via PulseAudio — let it finish. Counts active
    sink-inputs; ours appear there during paplay playback. Returns False on
    any failure."""
    try:
        r = subprocess.run(
            ["pactl", "list", "short", "sink-inputs"],
            capture_output=True, text=True, timeout=1,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False
    if r.returncode != 0:
        return False
    return any(line.strip() for line in r.stdout.splitlines())


def is_other_audio_playing(check_self: bool = True) -> bool:
    """Composite skip-decision. Despite the historical name, this answers
    'should I suppress this TTS?' — NOT 'is foreign audio playing?'.
    Foreign-app detection (WhatsApp, Spotify) is unreachable from non-root
    Termux on Android 16: cmd media_session, dumpsys, AudioPlaybackConfig
    all require signature permissions; termux-notification-list hangs
    without consent and is broken on Android 14+ (issue #621).

    The signals we DO have:
      1. Phone screen locked (ADB-over-localhost dumpsys window) — opt-in
         via setup-adb-pairing.sh; targets the 'phone in pocket / on
         table' case where the user isn't actively using the device.
      2. User-controlled pause flag (/pauza command).
      3. Device music-stream muted (termux-volume music==0).
      4. Self-coordination (already streaming via PulseAudio) — only
         consulted when check_self=True. Callers that intend to
         interrupt a still-playing turn (kill_previous=True) MUST pass
         check_self=False, otherwise the new turn would skip itself
         instead of killing the stale one.
    """
    if not is_screen_unlocked():
        return True
    if is_paused_by_user():
        return True
    if is_device_silenced():
        return True
    if check_self and is_self_already_speaking():
        return True
    return False


# Removed: is_mic_busy(). The mic-probe approach was unreliable because
# termux-microphone-record requires RECORD_AUDIO runtime permission; without
# that grant the binary spawns successfully but recording fails silently —
# the probe file stays at 0 bytes and the function returns busy=True forever.
# This produced a steady stream of false-positive SKIP reason=mic-busy events
# (visible in czytaj.log before 2026-04-28). Voice Typer's flag (is_recording)
# is the only reliable recording signal we have, and it's already checked.


def wait_for_recording_grace(timeout_s: float = 0.6, step_s: float = 0.05) -> bool:
    """Poll the recording flag for a short window before speaking.
    Voice Typer writes the flag asynchronously via MediaStore (~hundreds of ms),
    so a hook firing at the exact moment the user starts recording could miss it
    and read aloud during the recording. This polls briefly, returning True as
    soon as the flag appears (caller should then skip TTS)."""
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if os.path.isfile(VOICE_TYPER_FLAG):
            return True
        time.sleep(step_s)
    return False


def load_state() -> dict:
    """Read state with shared lock — safe against concurrent writers."""
    try:
        with open(STATE_FILE, "r") as f:
            try:
                fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            except OSError:
                pass
            try:
                return json.load(f)
            finally:
                try:
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
                except OSError:
                    pass
    except (OSError, ValueError):
        return {"last_uuid": "", "spoken_text": ""}


def save_state(state: dict) -> None:
    """Write state atomically (tempfile + os.replace) under exclusive lock so
    concurrent PreToolUse + Stop hooks can't lose updates."""
    spoken = state.get("spoken_text", "")
    if isinstance(spoken, str) and len(spoken.encode("utf-8")) > MAX_SPOKEN_TEXT_BYTES:
        encoded = spoken.encode("utf-8")[-MAX_SPOKEN_TEXT_BYTES:]
        try:
            spoken = encoded.decode("utf-8", errors="ignore")
        except Exception:
            spoken = spoken[-MAX_SPOKEN_TEXT_BYTES:]
        state = dict(state)
        state["spoken_text"] = spoken
    tmp_path = STATE_FILE + ".tmp"
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        fd = os.open(tmp_path, flags, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            with os.fdopen(fd, "w") as f:
                json.dump(state, f)
            fd = -1
        finally:
            if fd >= 0:
                try:
                    os.close(fd)
                except OSError:
                    pass
        os.replace(tmp_path, STATE_FILE)
        try:
            os.chmod(STATE_FILE, 0o600)
        except OSError:
            pass
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def reset_state_atomic() -> None:
    """Used by UserPromptSubmit hook — atomic empty state replaces non-atomic
    rm so a still-running Stop hook from the previous turn can't read empty."""
    save_state({"last_uuid": "", "spoken_text": ""})


def _parse_current_turn(transcript_path: str) -> tuple[str, str, str]:
    """Single parse pass. Returns (uuid, text, reason).
    reason is one of: 'ok', 'no-transcript', 'no-user-msg', 'all-tool-only'."""
    if not transcript_path or not os.path.isfile(transcript_path):
        return "", "", "no-transcript"
    home_real = os.path.realpath(os.path.expanduser("~/.claude"))
    try:
        path_real = os.path.realpath(transcript_path)
    except OSError:
        return "", "", "no-transcript"
    if not path_real.startswith(home_real + os.sep):
        return "", "", "no-transcript"
    try:
        with open(transcript_path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return "", "", "no-transcript"

    last_user_idx = -1
    for i, line in enumerate(lines):
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if msg.get("type") != "user":
            continue
        content = msg.get("message", {}).get("content", [])
        is_tool_result = False
        if isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    is_tool_result = True
                    break
        if not is_tool_result:
            last_user_idx = i

    if last_user_idx < 0:
        return "", "", "no-user-msg"

    texts: list[str] = []
    last_uuid = ""
    for line in lines[last_user_idx + 1:]:
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if msg.get("type") != "assistant":
            continue
        content = msg.get("message", {}).get("content", [])
        for c in content:
            if isinstance(c, dict) and c.get("type") == "text":
                t = c.get("text", "")
                if t:
                    texts.append(t)
        last_uuid = msg.get("uuid", "") or last_uuid

    if not texts:
        return last_uuid, "", "all-tool-only"
    return last_uuid, "\n".join(texts), "ok"


def current_turn_text(transcript_path: str) -> tuple[str, str]:
    """Return (last_uuid, concatenated_text) from all assistant messages
    that occurred AFTER the most recent user message.

    Anthropic issue #15813: Stop hook is spawned before the assistant
    message line is fsync'd to the transcript jsonl. A naive single read
    sometimes returns empty even though Claude DID emit text. Retry with
    exponential backoff (100ms→200ms→400ms→800ms = 1.5s budget) before
    giving up. Total fits within 10s hook timeout.

    Skip retry when the transcript is genuinely missing or has no user msg
    yet — those won't change by waiting."""
    delays = (0.1, 0.2, 0.4, 0.8)
    uuid = ""
    text = ""
    reason = "ok"
    for attempt in range(len(delays) + 1):
        uuid, text, reason = _parse_current_turn(transcript_path)
        if text or reason in ("no-transcript", "no-user-msg"):
            if attempt > 0:
                _log("RETRY", "succeeded-after", attempt, "reason=", reason)
            elif not text:
                _log("EMPTY", "reason=", reason)
            return uuid, text
        if attempt < len(delays):
            time.sleep(delays[attempt])
    _log("RETRY", "exhausted-empty", "reason=", reason)
    return uuid, text


def strip_markdown(text: str) -> str:
    t = text
    # Match fenced code blocks even when they contain single backticks (was a
    # bug: r'```[^`]*```' breaks on inline `code` inside fences).
    t = re.sub(r"```.*?```", " ", t, flags=re.DOTALL)
    t = re.sub(r"`([^`]+)`", r"\1", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"\1", t)
    t = re.sub(r"\*([^*]+)\*", r"\1", t)
    t = re.sub(r"^#+\s*", "", t, flags=re.MULTILINE)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    t = re.sub(r"^\s*[-*]\s+", ". ", t, flags=re.MULTILINE)
    t = re.sub(r"^\s*\d+\.\s+", ". ", t, flags=re.MULTILINE)
    t = re.sub(r"\n{2,}", ". ", t)
    t = re.sub(r"\s+", " ", t)
    return t.strip()


def _truncate_to_sentence(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    head = text[:limit]
    cut = head.rfind(".")
    if cut > limit // 2:
        return head[: cut + 1]
    return head


def _kill_audio_chain() -> None:
    for pat in ("termux-tts-speak", "termux-media-player", "piper_stream", "paplay"):
        subprocess.run(
            ["pkill", "-9", "-f", pat],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    # paplay leaves audio in PulseAudio sink-input buffer that keeps playing
    # for hundreds of ms after pkill. Forcibly drop all sink-inputs so the
    # buffer is flushed.
    try:
        r = subprocess.run(
            ["pactl", "list", "short", "sink-inputs"],
            capture_output=True, text=True, timeout=1,
        )
        for line in r.stdout.splitlines():
            sid = line.split("\t", 1)[0].strip()
            if sid.isdigit():
                subprocess.run(
                    ["pactl", "kill-sink-input", sid],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=1,
                )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass


def speak_new_text(transcript_path: str, kill_previous: bool) -> int:
    caller = "Stop" if kill_previous else "PreToolUse"
    _log("ENTER", caller, "transcript=", os.path.basename(transcript_path or ""))
    if not is_active():
        _log("SKIP", caller, "reason=mode-off")
        return 0
    if is_recording():
        _log("SKIP", caller, "reason=recording")
        return 0
    if is_in_call():
        _log("SKIP", caller, "reason=in-call")
        return 0
    # When kill_previous is True the caller intends to override any
    # in-flight TTS — skip the self-speaking check, otherwise we'd refuse
    # to interrupt our own stale playback and the new turn would be lost.
    if is_other_audio_playing(check_self=not kill_previous):
        _log("SKIP", caller, "reason=other-audio")
        return 0
    # Global lock — serializes concurrent hook fires (e.g. 5 PreToolUse hooks
    # racing when /petla spawns 5 validators in one message). Without this,
    # all 5 hooks load empty state, all decide to speak, and the same prefix
    # is repeated 5 times.
    try:
        lock_fd = os.open(SPEAK_LOCK, os.O_CREAT | os.O_RDWR, 0o600)
    except OSError:
        _log("LOCK", caller, "open-fail")
        return _speak_inner(transcript_path, kill_previous, caller)
    try:
        deadline = time.monotonic() + 2.0
        attempt = 0
        while True:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    _log("LOCK", caller, "timeout-give-up")
                    return 0
                attempt += 1
                time.sleep(0.05)
        if attempt:
            _log("LOCK", caller, "acquired-after", attempt, "tries")
        return _speak_inner(transcript_path, kill_previous, caller)
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        except OSError:
            pass


def _speak_inner(transcript_path: str, kill_previous: bool, caller: str = "?") -> int:

    uuid, full_text = current_turn_text(transcript_path)
    if not full_text.strip():
        _log("SKIP", caller, "reason=empty-turn-text")
        return 0

    state = load_state()
    _log("STATE", caller, "uuid=", uuid[:8], "spoken_len=", len(state.get("spoken_text", "")), "full_len=", len(full_text))
    if state.get("last_uuid") == uuid:
        already = state.get("spoken_text", "")
        if full_text.startswith(already):
            new_text = full_text[len(already):]
        else:
            new_text = full_text
    else:
        new_text = full_text

    new_text = new_text.strip()
    if not new_text:
        _log("SKIP", caller, "reason=no-new-text")
        return 0

    speakable = strip_markdown(new_text)
    if not speakable:
        _log("SKIP", caller, "reason=empty-after-strip")
        save_state({"last_uuid": uuid, "spoken_text": full_text})
        return 0

    speakable = _truncate_to_sentence(speakable, 2000)

    if kill_previous:
        _kill_audio_chain()

    if wait_for_recording_grace() or is_in_call() or not is_active():
        return 0

    # Mark this suffix as "already spoken" BEFORE we kick off playback. If a
    # new user message arrives mid-speech and aborts the player, this suffix
    # is intentionally lost (the new turn is more important than re-reading
    # the previous one — the user can ask again if needed). Without this,
    # interrupted playback caused the same message to be re-spoken next turn.
    save_state({"last_uuid": uuid, "spoken_text": full_text})
    _log("SPEAK", caller, "len=", len(speakable), "first40=", repr(speakable[:40]))

    preheat_audio()

    # Piper is the only supported engine. termux-tts-speak fallback was
    # removed because it hangs on Android 14+ (live test EXIT=124 at 3s)
    # and made every Piper failure look like an addon bug — the user heard
    # silence with no log signal. If Piper is missing, log loudly and bail
    # so install.sh's [!] warnings aren't masked at runtime.
    if not (os.path.isfile(PIPER_BIN) and os.path.isfile(PIPER_STREAM)):
        _log("ENGINE", "missing-piper", "bin=", os.path.isfile(PIPER_BIN),
             "stream=", os.path.isfile(PIPER_STREAM))
        return 0

    try:
        proc = subprocess.Popen(
            [sys.executable or "python3", PIPER_STREAM],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except (FileNotFoundError, OSError) as e:
        _log("ENGINE", "spawn-fail", repr(e))
        return 0

    try:
        proc.communicate(input=speakable.encode("utf-8"), timeout=2)
    except subprocess.TimeoutExpired:
        # Hand-off to piper_stream done; child runs in own session and
        # owns playback lifecycle. Don't kill — would interrupt the audio
        # the user is about to hear.
        pass
    except (BrokenPipeError, OSError) as e:
        _log("ENGINE", "stdin-pipe-fail", repr(e))

    return 0
