"""Shared speak logic for czytaj hooks.

State file tracks the last spoken assistant message uuid and the exact text
already spoken from it, so successive hooks (PreToolUse → ... → Stop) only
read the new suffix instead of repeating earlier content.
"""
import json
import os
import re
import subprocess
import time

FLAG_FILE = os.path.expanduser("~/.claude/czytaj.flag")
STATE_FILE = os.path.expanduser("~/.claude/czytaj-state.json")
SILENT_WAV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "silent.wav")
VOICE_TYPER_FLAG = os.path.expanduser(
    "~/storage/downloads/Termux-flags/voice-typer-recording.flag"
)


def preheat_audio() -> None:
    """Play a brief silent MUSIC-stream sample to wake Android Auto routing.
    Without this, after a phone call or fresh boot the TTS NOTIFICATION/MUSIC
    stream may be muted in the car until something else (e.g. Spotify) plays."""
    if not os.path.isfile(SILENT_WAV):
        return
    try:
        subprocess.Popen(
            ["termux-media-player", "play", SILENT_WAV],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        time.sleep(0.4)
    except FileNotFoundError:
        pass


def is_active() -> bool:
    return os.path.isfile(FLAG_FILE)


def is_recording() -> bool:
    return os.path.isfile(VOICE_TYPER_FLAG)


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
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"last_uuid": "", "spoken_text": ""}


def save_state(state: dict) -> None:
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except OSError:
        pass


def current_turn_text(transcript_path: str) -> tuple[str, str]:
    """Return (last_uuid, concatenated_text) from all assistant messages
    that occurred AFTER the most recent user message.
    Prevents reading stale prior-turn responses when the new turn has
    no text yet (e.g. starts with a tool call)."""
    if not transcript_path or not os.path.isfile(transcript_path):
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
        if msg.get("uuid"):
            last_uuid = msg.get("uuid", "")

    return last_uuid, "\n".join(texts)


def strip_markdown(text: str) -> str:
    t = text
    t = re.sub(r"```[^`]*```", " ", t, flags=re.DOTALL)
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


def speak_new_text(transcript_path: str, kill_previous: bool) -> int:
    if not is_active() or is_recording():
        return 0

    uuid, full_text = current_turn_text(transcript_path)
    if not full_text.strip():
        return 0

    state = load_state()
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
        return 0

    speakable = strip_markdown(new_text)
    if not speakable:
        save_state({"last_uuid": uuid, "spoken_text": full_text})
        return 0

    if len(speakable) > 2000:
        speakable = speakable[:2000].rsplit(".", 1)[0] + "."

    if kill_previous:
        subprocess.run(
            ["pkill", "-f", "termux-tts-speak"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    if wait_for_recording_grace():
        return 0

    preheat_audio()

    try:
        subprocess.Popen(
            ["termux-tts-speak", "-l", "pl-PL", "-s", "MUSIC", speakable],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except FileNotFoundError:
        return 0

    save_state({"last_uuid": uuid, "spoken_text": full_text})
    return 0
