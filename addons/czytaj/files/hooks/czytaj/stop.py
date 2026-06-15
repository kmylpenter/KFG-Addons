#!/usr/bin/env python3
"""Voice reader Stop hook: speak any unread suffix of the latest assistant message."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _speak import is_active, is_recording, is_in_call, speak_new_text  # noqa: E402


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    transcript = data.get("transcript_path", "")
    cwd = data.get("cwd", "")
    # On-demand VolumeUp read-back is INDEPENDENT of reading mode (the intended design): keep the
    # last N turns PRE-RENDERED in the read-back cache REGARDLESS of /czytaj on/off, so a press is
    # always an instant cache HIT, never a cold synth. This runs even with auto-read OFF because the
    # watcher's keepwarm sentinel keeps FLAG_DIR non-empty (so stop.sh still reaches us) and keeps the
    # daemon warm. Fire-and-forget; precache_turn skips already-cached turns, so it only synths the new one.
    _precache_latest(transcript)
    # F2: AUTO-READ (speaking the new text aloud) stays gated on the per-project flag + recording/call.
    # Gate keyed by the hook's project dir (data['cwd'] / CLAUDE_PROJECT_DIR), not os.getcwd().
    if not is_active(cwd) or is_recording() or is_in_call():
        return 0
    return speak_new_text(transcript, kill_previous=True, cwd=cwd)


def _precache_latest(transcript_path: str) -> None:
    if not transcript_path:
        return
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "precache.py")
    if not os.path.isfile(script):
        return
    try:
        import subprocess
        subprocess.Popen(
            [sys.executable or "python3", script, transcript_path, "5"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())
