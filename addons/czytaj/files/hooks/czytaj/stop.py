#!/usr/bin/env python3
"""Voice reader Stop hook: speak any unread suffix of the latest assistant message."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _speak import READBACK_CACHE_MAX  # noqa: E402


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
    # No AUTO-READ (Kamil 2026-10-07): reading is on demand only — a volume key plays the
    # pre-rendered turn. /czytaj ON just arms the keys; nothing is spoken here.
    return 0


def _precache_latest(transcript_path: str) -> None:
    if not transcript_path:
        return
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "precache.py")
    if not os.path.isfile(script):
        return
    try:
        import subprocess
        subprocess.Popen(
            [sys.executable or "python3", script, transcript_path, str(READBACK_CACHE_MAX)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())
