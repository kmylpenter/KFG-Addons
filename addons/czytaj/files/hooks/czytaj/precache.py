#!/usr/bin/env python3
"""Background pre-synth of a transcript turn into the read-back cache.

Spawned detached (start_new_session) by stop.py (latest turn, n=1) and by a
read_message_back cache MISS (the turn just read, n). Keeps read-back of recent
messages instant. Best-effort: any failure is swallowed so it never affects the
hook that launched it.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    if len(sys.argv) < 2:
        return 0
    transcript = sys.argv[1]
    n = 1
    if len(sys.argv) >= 3 and sys.argv[2].lstrip("-").isdigit():
        n = int(sys.argv[2])
    try:
        from _speak import precache_turn
        precache_turn(transcript, n)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
