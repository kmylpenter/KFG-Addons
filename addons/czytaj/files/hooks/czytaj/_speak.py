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
SHIZUKU_FLAG = os.path.expanduser("~/.claude/czytaj-shizuku.flag")
SCREEN_CACHE = os.path.expanduser("~/.claude/czytaj-screen.cache")
SCREEN_CACHE_TTL_S = 5.0
PROBE_CACHE_TTL_S = 5.0  # mic + media probes
# Multi-pane coordination: UPS hook writes the active session's transcript
# ID here; Stop hook reads it and SKIPS if its own transcript doesn't match.
# Prevents the X4 bug where 4 panes all read aloud when user prompts in one.
ACTIVE_SESSION_FILE = os.path.expanduser("~/.claude/czytaj-active-session.txt")
ACTIVE_SESSION_TTL_S = 300.0


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


def _transcript_id(transcript_path: str) -> str:
    """Stable identifier for a Claude session — the transcript jsonl basename."""
    if not transcript_path:
        return ""
    return os.path.basename(transcript_path)


def mark_active_session(transcript_path: str) -> None:
    """UPS hook calls this when a user prompt arrives in this session. Writes
    transcript_id + timestamp so only THIS pane will speak the resulting reply.
    Multi-pane fix (X4): without this gate, every Claude pane's Stop hook
    fires on its own transcript and they overlap audibly."""
    tid = _transcript_id(transcript_path)
    if not tid:
        return
    try:
        tmp = ACTIVE_SESSION_FILE + ".tmp"
        with open(tmp, "w") as f:
            f.write(f"{tid}\n{time.time():.3f}\n")
        os.replace(tmp, ACTIVE_SESSION_FILE)
        os.chmod(ACTIVE_SESSION_FILE, 0o600)
    except OSError:
        pass


def is_active_session(transcript_path: str) -> bool:
    """True iff this session is the one that most recently received a user
    prompt (within ACTIVE_SESSION_TTL_S). When False, Stop hook should SKIP —
    a different pane is the active one and will read aloud for the user.

    Fail open: if the active-session file is missing or unparseable, treat
    every session as active (preserves single-pane behaviour for users who
    never run multiple Claude instances)."""
    tid = _transcript_id(transcript_path)
    if not tid:
        return True
    try:
        with open(ACTIVE_SESSION_FILE) as f:
            lines = f.read().splitlines()
    except OSError:
        return True
    if len(lines) < 2:
        return True
    active_tid = lines[0].strip()
    try:
        marked_at = float(lines[1].strip())
    except ValueError:
        return True
    if time.time() - marked_at > ACTIVE_SESSION_TTL_S:
        return True
    return tid == active_tid


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


def _shell_cmd_prefix() -> list[str] | None:
    """Return the prefix that runs the next args with shell uid via Shizuku
    (preferred) or Wireless ADB (fallback). Returns None if neither is
    available — callers should fail open."""
    if os.path.isfile(SHIZUKU_FLAG):
        return ["rish", "-c"]
    if os.path.isfile(ADB_FLAG):
        return ["adb", "shell"]
    return None


def _run_shell(shell_cmd: str, timeout_s: float = 2.0) -> tuple[bool, str]:
    """Execute a single shell command via Shizuku/ADB. Returns (ok, stdout).
    ok==False means the helper isn't available or the call errored — caller
    must fail OPEN (don't suppress TTS just because a probe broke)."""
    prefix = _shell_cmd_prefix()
    if prefix is None:
        return False, ""
    if prefix[0] == "rish":
        cmd = prefix + [shell_cmd]
    else:
        cmd = prefix + shell_cmd.split()
    try:
        r = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout_s,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False, ""
    if r.returncode != 0:
        return False, r.stdout or ""
    return True, r.stdout


def is_screen_unlocked() -> bool:
    """True iff the user is actively interacting with the device.

    Uses dumpsys power's mWakefulness — most reliable single signal:
      Awake    → user is using device, return True
      Asleep   → screen off / in pocket, return False
      Dozing   → always-on display low-power, return False
      Dreaming → screensaver active, return False

    Earlier attempts at dumpsys window's mDreamingLockscreen/
    mShowingLockscreen were unreliable: on Pixels with Always-On
    Display, mDreamingLockscreen sticks at true for ~minutes after
    waking, blocking TTS during active use. mWakefulness flips
    immediately on touch/wake.

    Requires Shizuku or Wireless ADB. Cached 5s. Fails OPEN — missing
    helper or probe error → return True (don't suppress TTS just
    because the probe broke)."""
    if _shell_cmd_prefix() is None:
        return True
    cached = _read_screen_cache()
    if cached is not None:
        return cached
    ok, out = _run_shell(
        "dumpsys power | grep -m1 mWakefulness=",
        timeout_s=5.0,
    )
    if not ok:
        _write_screen_cache(True)
        return True
    unlocked = "mWakefulness=Awake" in out
    _write_screen_cache(unlocked)
    return unlocked


_IME_PACKAGES_CACHE: tuple[float, frozenset[str]] = (0.0, frozenset())


def _enabled_ime_packages() -> frozenset[str]:
    """Return the set of enabled input method (keyboard) package names.
    Keyboards like Voice Typer hold the microphone open whenever they're
    active — that doesn't mean the user is dictating right now. We must
    exclude IME packages from is_mic_recording_global() to avoid
    permanent TTS suppression. Cached for 5 minutes."""
    global _IME_PACKAGES_CACHE
    cached_at, cached = _IME_PACKAGES_CACHE
    if time.time() - cached_at < 300.0 and cached:
        return cached
    if _shell_cmd_prefix() is None:
        return frozenset()
    ok, out = _run_shell("ime list -s", timeout_s=5.0)
    if not ok:
        return cached
    pkgs = set()
    for line in out.splitlines():
        line = line.strip()
        if "/" in line:
            pkgs.add(line.split("/", 1)[0])
    if pkgs:
        _IME_PACKAGES_CACHE = (time.time(), frozenset(pkgs))
    return _IME_PACKAGES_CACHE[1]


def is_mic_recording_global() -> bool:
    """True iff any non-IME, non-Termux app currently records the
    microphone (e.g. WhatsApp voice msg, Messenger call, dictaphone).
    IME keyboards (Voice Typer, GBoard voice, etc.) hold the mic open
    persistently — they're filtered out so the addon isn't permanently
    muted whenever a voice-capable keyboard is enabled.

    Probe: dumpsys audio's per-session source client= entries, filtered
    by silenced:false (actively listening). Requires Shizuku or Wireless
    ADB. Fails open. Cached for 1s."""
    if _shell_cmd_prefix() is None:
        return False
    cache = os.path.expanduser("~/.claude/czytaj-mic.cache")
    try:
        if time.time() - os.stat(cache).st_mtime < PROBE_CACHE_TTL_S:
            return open(cache).read().strip() == "1"
    except OSError:
        pass
    ok, out = _run_shell(
        "dumpsys audio | grep -E 'source client=.*silenced:false.*pack:'",
        timeout_s=5.0,
    )
    recording = False
    if ok and out.strip():
        ime_pkgs = _enabled_ime_packages()
        for line in out.splitlines():
            pkg = ""
            for tok in line.split(" -- "):
                tok = tok.strip()
                if tok.startswith("pack:"):
                    pkg = tok[5:].strip()
                    break
            if not pkg or pkg in ime_pkgs:
                continue
            if pkg.startswith("com.termux") or "piper" in pkg:
                continue
            recording = True
            break
    try:
        with open(cache, "w") as f:
            f.write("1" if recording else "0")
        os.chmod(cache, 0o600)
    except OSError:
        pass
    return recording


def is_external_media_playing() -> bool:
    """True iff a foreign app (WhatsApp, Spotify, Messenger, YouTube...)
    has an active MediaSession in PLAYING state. Finally enables the
    'wait until WhatsApp voice msg finishes' behaviour the user asked
    about in the original audit.

    Requires Shizuku or Wireless ADB. Fails open. Cached for 1.5s."""
    if _shell_cmd_prefix() is None:
        return False
    cache = os.path.expanduser("~/.claude/czytaj-media.cache")
    try:
        if time.time() - os.stat(cache).st_mtime < PROBE_CACHE_TTL_S:
            return open(cache).read().strip() == "1"
    except OSError:
        pass
    ok, out = _run_shell(
        "cmd media_session list-sessions",
        timeout_s=5.0,
    )
    playing = False
    if ok and out:
        for line in out.splitlines():
            low = line.lower()
            if "state=playback_state_playing" in low or "state=3" in low:
                if "com.termux" in low or "piper" in low:
                    continue
                playing = True
                break
    try:
        with open(cache, "w") as f:
            f.write("1" if playing else "0")
        os.chmod(cache, 0o600)
    except OSError:
        pass
    return playing


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
    'should I suppress this TTS?'.

    When Shizuku (preferred) or Wireless ADB is configured, we get
    real foreign-app detection — the long-standing 'TTS gada w trakcie
    WhatsApp voicemsg' bug finally goes away. Without those helpers we
    fall back to the user-controlled signals only (pause flag, music
    volume, self-speaking).

    The signals we have, in order of evaluation:
      1. User-controlled pause flag (/pauza command).
      2. Phone screen locked (Shizuku/ADB dumpsys window) — kieszeń case.
      3. Foreign app holds microphone (Shizuku dumpsys audio) — don't
         talk over the user's voice typer recording.
      4. Foreign app actively plays media (Shizuku cmd media_session) —
         don't talk over WhatsApp voice message / Spotify / etc.
      5. Device music-stream muted (termux-volume music==0).
      6. Self-coordination (already streaming via PulseAudio) — only
         consulted when check_self=True. Callers that intend to
         interrupt a still-playing turn (kill_previous=True) MUST pass
         check_self=False, otherwise the new turn would skip itself
         instead of killing the stale one.
    """
    if is_paused_by_user():
        return True
    if not is_screen_unlocked():
        return True
    if is_mic_recording_global():
        return True
    if is_external_media_playing():
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
    if not is_active_session(transcript_path):
        _log("SKIP", caller, "reason=not-active-session")
        return 0
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
    already = state.get("spoken_text", "")
    _log("STATE", caller, "uuid=", uuid[:8], "spoken_len=", len(already), "full_len=", len(full_text))
    # Compare by CONTENT, not by UUID. A single turn can emit multiple
    # assistant messages with different UUIDs (think → say → tool → say
    # more); UPS hook resets spoken_text to "" at every new user prompt
    # so cross-turn re-reads are impossible. Within a turn, as long as
    # the latest full_text still starts with what we've already spoken,
    # we read only the suffix.
    if already and full_text.startswith(already):
        new_text = full_text[len(already):]
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
