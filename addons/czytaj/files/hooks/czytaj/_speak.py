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
import time

FLAG_FILE = os.path.expanduser("~/.claude/czytaj.flag")
STATE_FILE = os.path.expanduser("~/.claude/czytaj-state.json")
SPEAK_LOCK = os.path.expanduser("~/.claude/czytaj-speak.lock")
LOG_FILE = os.path.expanduser("~/.claude/czytaj.log")


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


def is_other_audio_playing() -> bool:
    """Stub — Termux's PulseAudio sandbox can't see Android system streams,
    and dumpsys is blocked without root."""
    return False


def is_mic_busy() -> bool:
    """Probe whether another app is recording via the device mic.
    We start a tiny background recording for 1 second; if data lands in the
    output file within ~250 ms, the mic is free (we got it). If the file
    stays at 0 bytes, another app is holding the mic — skip TTS."""
    probe = "/data/data/com.termux/files/usr/tmp/czytaj-mic-probe.m4a"
    try:
        os.unlink(probe)
    except OSError:
        pass
    try:
        subprocess.Popen(
            ["termux-microphone-record", "-d", "-l", "1", "-f", probe],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL, start_new_session=True,
        )
    except (FileNotFoundError, OSError):
        return False
    deadline = time.monotonic() + 0.4
    busy = True
    while time.monotonic() < deadline:
        try:
            if os.path.getsize(probe) > 0:
                busy = False
                break
        except OSError:
            pass
        time.sleep(0.05)
    try:
        subprocess.run(
            ["termux-microphone-record", "-q"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=1,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    try:
        os.unlink(probe)
    except OSError:
        pass
    return busy


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


def current_turn_text(transcript_path: str) -> tuple[str, str]:
    """Return (last_uuid, concatenated_text) from all assistant messages
    that occurred AFTER the most recent user message.
    Prevents reading stale prior-turn responses when the new turn has
    no text yet (e.g. starts with a tool call)."""
    if not transcript_path or not os.path.isfile(transcript_path):
        return "", ""
    home_real = os.path.realpath(os.path.expanduser("~/.claude"))
    try:
        path_real = os.path.realpath(transcript_path)
    except OSError:
        return "", ""
    if not path_real.startswith(home_real + os.sep):
        return "", ""
    try:
        with open(transcript_path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return "", ""

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
        return "", ""

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

    return last_uuid, "\n".join(texts)


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
    if is_other_audio_playing():
        _log("SKIP", caller, "reason=other-audio")
        return 0
    # Mic probe disabled — gives too many false positives (Android audio
    # service slow to release mic after YouTube/etc.). Voice Typer's flag
    # is checked separately via is_recording() which is reliable.
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

    use_piper = os.path.isfile(PIPER_BIN) and os.path.isfile(PIPER_STREAM)

    try:
        if use_piper:
            proc = subprocess.Popen(
                ["python3", PIPER_STREAM],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                proc.communicate(input=speakable.encode("utf-8"), timeout=2)
            except subprocess.TimeoutExpired:
                pass
            except (BrokenPipeError, OSError):
                pass
        else:
            subprocess.Popen(
                ["termux-tts-speak", "-l", "pl-PL", "-s", "MUSIC", speakable],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
    except FileNotFoundError:
        return 0

    return 0
