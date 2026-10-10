#!/usr/bin/env python3
"""Voice reader PreToolUse hook: speak any text added since the last hook run."""
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
    # Streaming read-aloud before tool calls — only where /czytaj is ON (Kamil 2026-10-10).
    # F2: gate keyed by the hook's project dir (data['cwd']), not os.getcwd().
    if not is_active(data.get("cwd", "")) or is_recording() or is_in_call():
        return 0
    return speak_new_text(
        data.get("transcript_path", ""),
        kill_previous=True,
        cwd=data.get("cwd", ""),
    )


if __name__ == "__main__":
    sys.exit(main())
