#!/usr/bin/env python3
"""Voice reader Stop hook: speak any unread suffix of the latest assistant message."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _speak import is_active, is_recording, is_in_call, speak_new_text  # noqa: E402


def main() -> int:
    if not is_active() or is_recording() or is_in_call():
        return 0
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    return speak_new_text(data.get("transcript_path", ""), kill_previous=True)


if __name__ == "__main__":
    sys.exit(main())
