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
    # F2: gate on the per-project flag keyed by the hook's project dir (data['cwd']
    # / CLAUDE_PROJECT_DIR), not os.getcwd() — read data BEFORE the is_active check.
    if not is_active(data.get("cwd", "")) or is_recording() or is_in_call():
        return 0
    transcript = data.get("transcript_path", "")
    rc = speak_new_text(transcript, kill_previous=True, cwd=data.get("cwd", ""))
    # Background pre-synth of the latest turn → read-back cache (instant re-read).
    # Only here, where reading is confirmed on for this window. Fire-and-forget.
    _precache_latest(transcript)
    return rc


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
