#!/usr/bin/env python3
"""czytaj volume-key watcher.

Reads raw kernel key events from the volume-key input device via Shizuku and
maps the hardware volume keys to czytaj actions while reading mode is ON:

    Volume Down  -> pause / resume the current TTS (media-player style, toggles)
    Volume Up    -> re-read the active session's last message from the top

Why a raw binary read (dd) instead of `getevent`: piping `getevent -l` through
the Shizuku shell block-buffered its stdout — events arrived in bursts or not at
all, and a connection that went stale after device sleep delivered nothing while
the process stayed alive. `dd bs=24` does a raw write() per event (no stdio
buffering) so each press reaches us immediately, and a select() idle-timeout
restarts a silent reader so a stale Shizuku/sleep connection self-heals.

getevent is PASSIVE: the keys still change system volume (consuming them would
need EVIOCGRAB, which blocks volume control entirely). We only ACT on the press,
and only while reading is ON, so volume control isn't hijacked when idle.

Lifecycle: spawned by toggle.sh on the first project ON; killed on the last OFF.
"""
from __future__ import annotations

import fcntl
import os
import select
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _speak import _log, read_message_back  # noqa: E402

FLAG_DIR = os.path.expanduser("~/.claude/czytaj-flags")
SHIZUKU_FLAG = os.path.expanduser("~/.claude/czytaj-shizuku.flag")
LOCK_FILE = os.path.expanduser("~/.claude/czytaj-volume-watcher.lock")

# struct input_event on 64-bit Linux (aarch64): struct timeval {long sec; long usec;}
# = 16 bytes, then __u16 type + __u16 code + __s32 value = 8 bytes -> 24 total.
_EV_SIZE = 24
_EV_FMT = "<qqHHi"
EV_KEY = 0x01
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
PRESS = 1  # value: 1=down/press, 0=up/release, 2=autorepeat (we act on press only)

DEBOUNCE_S = 0.4               # ignore a repeat of the same key within this window
RESPAWN_DELAY_S = 3.0          # back-off after the reader exits
IDLE_RECHECK_S = 5.0           # poll interval while Shizuku/rish is unavailable
READER_IDLE_RESTART_S = 60.0  # heal a STALE reader fast. The Shizuku dd stream goes SILENT
                              # (process alive, delivering nothing) after device doze, so the
                              # select() idle-timeout re-spawns it within ~a minute of silence.
                              # Restarts are cheap because the device path is cached (no re-probe).
DEVICE_ENV = "CZYTAJ_VOLUME_DEVICE"
# Foreground gate: the volume keys drive czytaj ONLY while the user is actually
# looking at Termux (the terminal is the focused app). Pressed from any other app /
# home screen / lock screen they just do their normal volume job — so a stray press
# (e.g. at bedtime) can't trigger a re-read, while on-demand read-last stays
# available any time you're in the terminal. Termux also intercepts the keys when
# it is foreground, so this is exactly when they DON'T change the system volume.
TERMUX_PKG = "com.termux"
FG_CACHE_TTL_S = 30.0  # foreground changes slowly; cache long so back-to-back presses (which
                       # land 10-40s apart through the slow relay) don't each re-pay the ~1.8s
                       # dumpsys focus check. 30s still re-blocks the bedtime stray-press case.

# Local pause state for a FAST VolumeDown toggle — avoids a slow `termux-media-player
# info` round-trip on every press. Self-correcting: after one press it matches reality.
_paused = False

# Read-back counter: VolumeUp reads the last message; pressed again while a read is
# still playing it steps one message further back (2=previous, 3=older, …). Resets to
# the last message once playback has finished (idle) before the next press.
_readback_n = 0
_last_read_ts = 0.0
READBACK_WINDOW_S = 45.0  # consecutive VolumeUp presses within this window step further back.
                          # Generous because the Shizuku relay + a full read can put 10-40s
                          # between presses; a shorter window reset to 1 every time (the bug
                          # where it always re-read the same message). Reset also on VolumeDown.


def _reading_on() -> bool:
    """True iff at least one project currently has reading mode ON."""
    try:
        with os.scandir(FLAG_DIR) as it:
            return any(True for _ in it)
    except OSError:
        return False


def _shizuku_ready() -> bool:
    return os.path.isfile(SHIZUKU_FLAG)


_fg_cache = {"t": 0.0, "v": False}


def _termux_foreground() -> bool:
    """True iff Termux is the focused/foreground app (checked via the focused
    window's package). Cached for FG_CACHE_TTL_S so a burst of presses stays snappy.
    Fails CLOSED (False) on error: if we can't confirm the user is in Termux, leave
    the keys to their normal volume job rather than risk a spurious re-read."""
    now = time.monotonic()
    if now - _fg_cache["t"] < FG_CACHE_TTL_S:
        return _fg_cache["v"]
    val = False
    try:
        out = subprocess.run(
            ["rish", "-c", "dumpsys window 2>/dev/null | grep -m1 mCurrentFocus"],
            capture_output=True, text=True, timeout=4,
        ).stdout
        val = TERMUX_PKG in out
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        val = False
    _fg_cache["t"] = now
    _fg_cache["v"] = val
    return val


def _single_instance() -> "int | None":
    """Hold an exclusive lock so only one watcher runs. Returns the held fd (keep
    it open for the process lifetime) or None if another instance owns it."""
    try:
        fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o600)
    except OSError:
        return None
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        try:
            os.close(fd)
        except OSError:
            pass
        return None
    return fd


def _discover_volume_device() -> str:
    """/dev/input/eventN exposing the volume keys (gpio_keys), or '' (caller then
    reads event0). Parsed on the Android side via awk so only the single path
    crosses the rish relay. Retried — getevent -lp occasionally returns empty."""
    override = os.environ.get(DEVICE_ENV, "").strip()
    if override:
        return override
    script = ("getevent -lp 2>/dev/null | "
              "awk '/^add device/{d=$4} /KEY_VOLUMEUP/{print d; exit}'")
    for _ in range(3):
        try:
            out = subprocess.run(["rish", "-c", script],
                                 capture_output=True, text=True, timeout=15).stdout.strip()
        except (subprocess.SubprocessError, FileNotFoundError, OSError):
            out = ""
        if out:
            return out.splitlines()[0].strip()
        time.sleep(0.5)
    return ""


def _media(cmd: str) -> None:
    try:
        subprocess.run(["termux-media-player", cmd],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass


# Keep the CPU awake while reading mode is ON. The Shizuku key-reader FREEZES when
# the device dozes (a slept CPU delivers no dd events) — that was every "I pressed
# and nothing happened" after a quiet spell or a pause. A partial wakelock, held by
# main() for as long as ANY project has reading on, stops the doze so every press
# reaches us; released when all reading is off (battery back to normal, on-demand
# keys still work best-effort). Tracked so we never spawn a redundant lock/unlock.
_wake_held = False


def _wake_lock() -> None:
    global _wake_held
    if _wake_held:
        return
    try:
        subprocess.run(["termux-wake-lock"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
        _wake_held = True
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass


def _wake_unlock() -> None:
    global _wake_held
    if not _wake_held:
        return
    _wake_held = False
    try:
        subprocess.run(["termux-wake-unlock"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass


def _toggle_pause() -> None:
    """VolumeDown: pause the current TTS at its position, or resume if paused —
    media-player style. Uses a local state flag (no slow status query) for snappy
    response, sending termux-media-player pause/play accordingly."""
    global _paused, _readback_n
    _readback_n = 0  # VolumeDown breaks any VolumeUp read-back scrubbing sequence
    if _paused:
        _media("play")
        _paused = False
        _log("VOLKEY", "resume")
    else:
        _media("pause")
        _paused = True
        _log("VOLKEY", "pause")


def _read_back() -> None:
    """VolumeUp: read the last message; pressed again within READBACK_WINDOW_S of the
    previous press, step one message further back (rapid presses scrub back). A press
    after a longer gap resets to the last message. No media-status query — that
    Android call cost ~1.7s; the time window approximates 'still scrubbing'."""
    global _paused, _readback_n, _last_read_ts
    _paused = False
    now = time.monotonic()
    _readback_n = _readback_n + 1 if (now - _last_read_ts) < READBACK_WINDOW_S else 1
    _last_read_ts = now
    _log("VOLKEY", "VolumeUp -> read-back", _readback_n)
    try:
        read_message_back(_readback_n)
    except Exception as e:  # never let one bad action kill the watcher
        _log("VOLKEY", "read-back-error", repr(e))


def _stream(device: str) -> None:
    """Read raw input_event structs from `device` via `dd` (raw write() per event,
    NO stdio buffering) and dispatch volume-key presses. Returns when the reader
    exits OR after READER_IDLE_RESTART_S of silence (self-heal a stale link)."""
    dev = device or "/dev/input/event0"
    cmd = ["rish", "-c", f"dd if={dev} bs={_EV_SIZE} 2>/dev/null"]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, bufsize=0)
    except (FileNotFoundError, OSError) as e:
        _log("VOLKEY", "reader-spawn-fail", repr(e))
        return
    buf = b""
    last_fire: dict[int, float] = {}
    try:
        assert proc.stdout is not None
        fd = proc.stdout.fileno()
        while True:
            rlist, _, _ = select.select([fd], [], [], READER_IDLE_RESTART_S)
            if not rlist:
                _log("VOLKEY", "reader idle-restart (heal stale link)")
                break
            chunk = os.read(fd, 4096)
            if not chunk:
                break  # reader (dd / rish) exited
            buf += chunk
            while len(buf) >= _EV_SIZE:
                ev, buf = buf[:_EV_SIZE], buf[_EV_SIZE:]
                try:
                    _s, _u, etype, code, value = struct.unpack(_EV_FMT, ev)
                except struct.error:
                    continue
                if etype != EV_KEY or value != PRESS:
                    continue  # release / autorepeat / non-key
                if code not in (KEY_VOLUMEDOWN, KEY_VOLUMEUP):
                    continue
                if not _termux_foreground():
                    continue  # Termux not the focused app → leave the volume keys to
                    #            their normal job. The keys are a GLOBAL remote now,
                    #            independent of czytaj on/off (czytaj on/off gates only
                    #            AUTO-reading); on-demand read-back/pause work any time
                    #            you're in the terminal, whether reading mode is on or off.
                now = time.monotonic()
                if now - last_fire.get(code, 0.0) < DEBOUNCE_S:
                    continue
                last_fire[code] = now
                if code == KEY_VOLUMEDOWN:
                    _toggle_pause()
                else:
                    _read_back()
    except OSError:
        pass
    finally:
        try:
            proc.kill()
        except OSError:
            pass


def main() -> int:
    lock_fd = _single_instance()
    if lock_fd is None:
        return 0  # another watcher already owns the lock
    _log("VOLKEY", "watcher start pid=", os.getpid())
    device = ""
    try:
        while True:
            # Reliable delivery: hold a CPU wakelock while any project is reading so
            # the device can't doze and freeze the Shizuku key-reader. Re-evaluated
            # each loop so it follows a czytaj on→off toggle within a cycle.
            if _reading_on():
                _wake_lock()
            else:
                _wake_unlock()
            if not _shizuku_ready():
                time.sleep(IDLE_RECHECK_S)
                continue
            if not device:  # discover once, then reuse so stale-reader restarts are cheap
                device = _discover_volume_device()
                _log("VOLKEY", "reading", device or "/dev/input/event0", "(dd binary)")
            start = time.monotonic()
            _stream(device)
            # If the reader died almost instantly the cached device path is likely
            # stale (e.g. event nodes renumbered after a reboot) — re-probe next loop.
            if device and (time.monotonic() - start) < 2.0:
                device = ""
            time.sleep(RESPAWN_DELAY_S)
    finally:
        _wake_unlock()  # never leave the CPU pinned awake after the watcher stops
        _log("VOLKEY", "watcher exit")
        try:
            os.close(lock_fd)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
