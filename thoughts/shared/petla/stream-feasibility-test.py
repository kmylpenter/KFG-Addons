#!/usr/bin/env python3
"""Feasibility probe for sentence-streaming read-back (does synth keep ahead of playback,
and how big is the per-sentence play am-boot gap). Plays 3 short test sentences."""
import os, sys, time, wave, tempfile, subprocess, threading
from pathlib import Path

sys.path.insert(0, os.path.expanduser("~/.claude/hooks/czytaj"))
import piper_server as ps


def synth(text):
    w = Path(tempfile.mktemp(suffix=".wav"))
    t = time.monotonic()
    ok = ps.speak(text, w)
    return w, time.monotonic() - t, ok


def wav_dur(w):
    try:
        with wave.open(str(w)) as f:
            return f.getnframes() / float(f.getframerate())
    except Exception:
        return 0.0


def play_blocking(w):
    """Fire play, return (am_boot_fire_s, total_play_s). am_boot = time for the play
    command to return (≈ time to first audio)."""
    t = time.monotonic()
    subprocess.run(["termux-media-player", "play", str(w)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    fired = time.monotonic() - t
    while True:
        r = subprocess.run(["termux-media-player", "info"],
                           capture_output=True, text=True, timeout=8)
        if "Playing" not in (r.stdout or ""):
            break
        time.sleep(0.2)
    return fired, time.monotonic() - t


s1 = "To jest pierwsze zdanie testu streamingu."
s2 = "A to drugie zdanie, ktore syntezujemy w tle, gdy pierwsze juz gra przez glosnik."
s3 = "Trzecie zdanie zamyka probe."

print("=== synth S1 (the first chunk — this is the new 'time to first audio') ===")
w1, st1, _ = synth(s1)
d1 = wav_dur(w1)
print(f"S1: synth={st1:.2f}s  audio_len={d1:.2f}s")

# Play S1 (blocking) WHILE a producer thread synths S2+S3 concurrently.
res = {}
def producer():
    t = time.monotonic()
    res["w2"], res["st2"], _ = synth(s2)
    res["w3"], res["st3"], _ = synth(s3)
    res["prod_total"] = time.monotonic() - t

pt = threading.Thread(target=producer)
pt.start()
fired1, tot1 = play_blocking(w1)
pt.join()
print(f"S1 play: am_boot(time-to-audio)={fired1:.2f}s  total_play={tot1:.2f}s")
print(f"producer synthed S2+S3 in {res['prod_total']:.2f}s while S1 played for {tot1:.2f}s")
ahead = res["prod_total"] < tot1
print(f">>> SYNTH KEEPS AHEAD OF PLAYBACK: {ahead}  (if True, no synth-gap after sentence 1)")

# Play S2 right after S1 ended → its am_boot IS the inter-sentence silence gap.
fired2, tot2 = play_blocking(res["w2"])
print(f"S2 play: am_boot(INTER-SENTENCE GAP)={fired2:.2f}s  <-- silence between sentences")
fired3, _ = play_blocking(res["w3"])
print(f"S3 play: am_boot={fired3:.2f}s")

print("")
print("=== VERDICT INPUTS ===")
print(f"time-to-first-audio (stream) ~= synth_S1 + am_boot = {st1 + fired1:.2f}s")
print(f"per-sentence GAP from play am-boot ~= {fired2:.2f}s (this is the choppiness cost)")
print(f"synth-stays-ahead = {ahead}")

for w in (w1, res.get("w2"), res.get("w3")):
    try:
        if w:
            os.unlink(w)
    except OSError:
        pass
