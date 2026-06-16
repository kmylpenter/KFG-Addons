#!/usr/bin/env python3
"""Single source of truth for czytaj runtime paths, the Piper install layout, the
synth config defaults, and the per-project key.

WHY THIS EXISTS (SSOT audit 2026-06-15, findings S1–S5): every czytaj executable used
to re-declare these as literals — FLAG_DIR in 7 places, RUN_DIR hardcoded in 3, the
sha1 project key derived in 3 files across two languages, the piper-home resolver
copy-pasted 3×, the voice/rate/length defaults duplicated server↔stream — all kept
aligned by hand-maintained "MUST match X" comments. The RUN_DIR copy is the value whose
earlier divergence split the daemon and made synth ALWAYS cold (~3–7 s). Centralising the
VALUES here makes that whole class of drift structurally impossible.

Values are exported as STRINGS on purpose: a str works with os.path.*, open(), subprocess
AND Path(str), so the str-based callers (_speak.py, volume_watcher.py) import them as
drop-in replacements with zero usage change, while the Path-based callers (piper_server.py,
piper_stream.py) wrap the few they use Path-API on in Path(...) locally. The shell side has
its own single source (czytaj-env.sh); a canary in czytaj_selftest.py pins the cross-language
sha1 key so the two never drift.

Only stdlib; safe to import from any czytaj hook.
"""
from __future__ import annotations

import hashlib
import os

# ── Base dirs ───────────────────────────────────────────────────────────────
CLAUDE_DIR = os.path.expanduser("~/.claude")


def _claude(name: str) -> str:
    return os.path.join(CLAUDE_DIR, name)


# ── Termux / Android shared-storage layout (M6/M16/M17, audit 2026-06-15) ───────
# These absolute paths are used by termux-media-player and the keyboard app, both OUTSIDE
# PRoot; PRoot's ~ does NOT map to them, so they can't be ~-expanded and were duplicated as
# literals across 4 files. One source here ends that drift.
TERMUX_HOME = "/data/data/com.termux/files/home"
TERMUX_PREFIX = "/data/data/com.termux/files/usr"
# Shared-storage flags dir the keyboard app (a separate Android uid) and czytaj (PRoot) both
# reach. ~/storage/downloads/Termux-flags symlinks here — same physical dir (verified).
TERMUX_FLAGS_DIR = os.environ.get(
    "CZYTAJ_TERMUX_FLAGS_DIR", "/storage/emulated/0/Download/Termux-flags")


def first_writable_dir(candidates, probe: bool = False) -> str:
    """First dir in `candidates` that can be created (and, with probe=True, actually written
    to). Returns "" if none succeeds. Callers staging audio for termux-media-player MUST treat
    "" as 'no Android-readable dir' and NOT fall back to a PRoot tempdir — the player can't see
    PRoot paths (ENOENT -> silent TTS, the F11 bug)."""
    for d in candidates:
        try:
            os.makedirs(d, exist_ok=True)
            if probe:
                wt = os.path.join(d, ".wtest")
                with open(wt, "w") as fh:
                    fh.write("x")
                os.remove(wt)
            return d
        except OSError:
            continue
    return ""


# Candidate dirs (first writable wins) for the two Termux-readable audio scratch areas that
# were near-duplicate try-each-dir loops in piper_stream (_audio_scratch_dir, write-probed)
# and _speak (_readback_cache_base). Keep the order in sync with those resolvers.
AUDIO_SCRATCH_DIRS = (os.path.join(TERMUX_HOME, ".cache", "czytaj"),
                      os.path.join(TERMUX_PREFIX, "tmp"))
READBACK_CACHE_DIRS = (os.path.join(TERMUX_HOME, ".cache", "czytaj", "readback"),
                       os.path.join(TERMUX_PREFIX, "tmp", "czytaj-readback"))


# ── Per-project reading-mode flags (F1/F15: per-project, was a global flag) ──
FLAG_DIR = _claude("czytaj-flags")            # dir of <sha1(realpath)>.flag

# ── Shared runtime state (~/.claude/czytaj-*) ───────────────────────────────
STATE_FILE = _claude("czytaj-state.json")
SPEAK_LOCK = _claude("czytaj-speak.lock")
LOG_FILE = _claude("czytaj.log")
PAUSE_FLAG = _claude("czytaj-pause.flag")
ADB_FLAG = _claude("czytaj-adb.flag")
SHIZUKU_FLAG = _claude("czytaj-shizuku.flag")
SCREEN_CACHE = _claude("czytaj-screen.cache")
ACTIVE_SESSION_FILE = _claude("czytaj-active-session.txt")
SPOKEN_LEDGER = _claude("czytaj-spoken-ledger.json")
LAST_FOLDER_FILE = _claude("czytaj-last-folder.txt")
MIC_CACHE = _claude("czytaj-mic.cache")
MEDIA_CACHE = _claude("czytaj-media.cache")
VOL_CACHE = _claude("czytaj-vol.cache")
WATCHER_LOCK = _claude("czytaj-volume-watcher.lock")

# Cross-process play/pause/heartbeat markers (written by one process, read by another —
# these MUST be one value or a writer and reader silently disagree).
PREHEAT_MARKER = _claude("czytaj-preheat.ts")
KEYPAUSE_STATE = _claude("czytaj-keypause.state")
PLAYING_MARKER = _claude("czytaj-playing.flag")
CHANNEL_FILE = _claude("czytaj-channel")

# ── In-turn audio-client kill patterns (M13 — was triplicated: toggle.sh/user-prompt-submit.sh/_speak.py) ─
# The short-lived playback clients pkill'd on a new turn / teardown. NEVER piper_server/piper-daemon
# (the warm daemon must survive — keepwarm). Mirrored by czytaj-env.sh's CZYTAJ_AUDIO_CLIENT_PATS
# bash array; czytaj_selftest pins shell == python. F21: piper_stream anchored to its python invocation.
AUDIO_CLIENT_PATS = ("termux-tts-speak", "termux-media-player", "paplay", r"python.*piper_stream\.py")

# ── Piper daemon run dir (S2 — the daemon-split landmine; ONE definition now) ─
# FIXED path (was XDG_RUNTIME_DIR/TMPDIR-derived): those env vars DIFFER across czytaj
# processes, so each computed a DIFFERENT dir → separate daemons that never shared the
# socket → synth ALWAYS cold (~3–7 s) + zombies. A stable HOME path makes every process
# (watcher, Stop hook, precache, piper_stream) share ONE warm daemon. czytaj-env.sh mirrors
# this for the shell side; czytaj_selftest.py asserts they agree.
RUN_DIR = os.path.expanduser("~/.cache/czytaj/piper-server")
SOCKET_PATH = os.path.join(RUN_DIR, "server.sock")
PID_FILE = os.path.join(RUN_DIR, "server.pid")
SERVER_LOCK = os.path.join(RUN_DIR, "server.lock")

# ── Synth config defaults (S5 — were duplicated server↔stream) ──────────────
PIPER_VOICE = os.environ.get("PIPER_VOICE", "pl_PL-gosia-medium")
try:
    PIPER_SAMPLE_RATE = int(os.environ.get("PIPER_SAMPLE_RATE", "22050"))
except ValueError:
    PIPER_SAMPLE_RATE = 22050
PIPER_LENGTH_SCALE = os.environ.get("PIPER_LENGTH_SCALE", "0.6")  # str (env passthrough)
VOICE_TYPER_STALE_S = 3.0  # keyboard heartbeats ≤1s; ignore a flag older than this (crashed)


# ── Piper install layout (S4 — resolver was copy-pasted 3×) ─────────────────
def resolve_piper_home() -> str:
    """Locate the piper-tts install. Order: $PIPER_HOME, then ~/piper-tts, then the old
    Termux home (piper may have been built under /data/data/com.termux/files/home before a
    native/PRoot switch moved HOME to /root). First layout that contains the binary wins."""
    env = os.environ.get("PIPER_HOME")
    if env:
        return env
    for home in (os.path.expanduser("~/piper-tts"),
                 os.path.join(TERMUX_HOME, "piper-tts")):
        if os.path.isfile(os.path.join(home, "piper1-gpl", "libpiper", "piper")):
            return home
    return os.path.expanduser("~/piper-tts")


PIPER_HOME = resolve_piper_home()
PIPER_BIN = os.path.join(PIPER_HOME, "piper1-gpl", "libpiper", "piper")
PIPER_DAEMON = os.path.join(PIPER_HOME, "piper1-gpl", "libpiper", "piper-daemon")
PIPER_LIB = os.path.join(PIPER_HOME, "piper1-gpl", "libpiper", "install", "lib")
PIPER_ESPEAK = os.path.join(PIPER_HOME, "piper1-gpl", "libpiper", "install", "espeak-ng-data")
PIPER_VOICES = os.path.join(PIPER_HOME, "voices")


def resolve_voice_typer_flag() -> str:
    """Voice Typer (a separate Android uid) writes its recording flag under the shared
    Termux-flags dir. Prefer the canonical absolute base (TERMUX_FLAGS_DIR — the path the
    writer uses); on native PRoot HOME is /root and ~/storage does NOT exist, so also try the
    home-relative twins (same physical dir via the storage symlink, verified). First whose
    parent dir exists wins. Without this, is_recording() returned False on native PRoot and
    dictation could never interrupt TTS."""
    name = "voice-typer-recording.flag"
    rel = "storage/downloads/Termux-flags/" + name
    candidates = (os.path.join(TERMUX_FLAGS_DIR, name),
                  os.path.join(os.path.expanduser("~"), rel),
                  os.path.join(TERMUX_HOME, rel))
    for cand in candidates:
        if os.path.isdir(os.path.dirname(cand)):
            return cand
    return os.path.expanduser("~/" + rel)


VOICE_TYPER_FLAG = resolve_voice_typer_flag()


# ── Per-project key (S3 — sha1 of realpath; was derived in 3 files, 2 languages) ─
def project_dir(cwd: str = "") -> str:
    """The ONE canonical project dir for the per-project key (F1/F5). Order:
    $CLAUDE_PROJECT_DIR (stable even after `cd` into a subdir) → the hook's data['cwd'] →
    os.getcwd(). czytaj-env.sh resolves the SAME source (${CLAUDE_PROJECT_DIR:-$PWD})."""
    return os.environ.get("CLAUDE_PROJECT_DIR") or cwd or os.getcwd()


def project_key(cwd: str = "") -> str:
    """sha1 of the project dir's realpath. MUST equal czytaj-env.sh's czytaj_project_key:
        printf '%s' "$(realpath "${CLAUDE_PROJECT_DIR:-$PWD}")" | sha1sum
    (printf '%s' — NOT echo, whose trailing newline would change the hash). Pinned by the
    canary in czytaj_selftest.py."""
    d = os.path.realpath(project_dir(cwd))
    return hashlib.sha1(d.encode("utf-8")).hexdigest()


def project_flag(cwd: str = "") -> str:
    """Per-project reading-mode flag path."""
    return os.path.join(FLAG_DIR, project_key(cwd) + ".flag")


if __name__ == "__main__":
    # CLI for the shell canary + manual inspection: `python3 czytaj_paths.py key [DIR]`
    import sys
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "key":
        # Hash the realpath of the LITERAL dir arg (matches czytaj-env.sh's
        # czytaj_project_key), bypassing project_dir's env resolution so the shell
        # canary compares the ALGORITHM, not whichever env happens to be set.
        d = sys.argv[2] if len(sys.argv) > 2 else project_dir("")
        print(hashlib.sha1(os.path.realpath(d).encode("utf-8")).hexdigest())
    elif arg == "run_dir":
        print(RUN_DIR)
    elif arg == "flag_dir":
        print(FLAG_DIR)
    else:
        print(f"PIPER_HOME={PIPER_HOME}")
        print(f"RUN_DIR={RUN_DIR}")
        print(f"FLAG_DIR={FLAG_DIR}")
        print(f"PIPER_VOICE={PIPER_VOICE} rate={PIPER_SAMPLE_RATE} length={PIPER_LENGTH_SCALE}")
