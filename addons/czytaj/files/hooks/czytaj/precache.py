#!/usr/bin/env python3
"""Background pre-synth of recent transcript turns into the read-back cache.

Spawned detached (start_new_session) by stop.py (the active window's last turns)
and by a read_message_back cache MISS. The 2nd arg is a MAX depth: we pre-synth
turns n=1..maxn so the last `maxn` assistant turns stay warm — fixing the bug
where caching only n=1 left re-reads of older turns as misses. Best-effort: any
failure is swallowed so it never affects the hook that launched it.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    if len(sys.argv) < 2:
        return 0
    transcript = sys.argv[1]
    maxn = 1
    if len(sys.argv) >= 3 and sys.argv[2].lstrip("-").isdigit():
        maxn = max(1, int(sys.argv[2]))
    try:
        from _speak import precache_turn
        for n in range(1, maxn + 1):
            precache_turn(transcript, n)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
