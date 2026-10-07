#!/usr/bin/env python3
"""Voice reader PreToolUse hook: speak any text added since the last hook run."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    # No streaming read-aloud before tool calls (Kamil 2026-10-07): reading is on demand only.
    return 0


if __name__ == "__main__":
    sys.exit(main())
