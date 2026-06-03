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
import signal
import struct
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _speak import _log, read_message_back, is_readback_playing  # noqa: E402

FLAG_DIR = os.path.expanduser("~/.claude/czytaj-flags")
SHIZUKU_FLAG = os.path.expanduser("~/.claude/czytaj-shizuku.flag")
LOCK_FILE = os.path.expanduser("~/.claude/czytaj-volume-watcher.lock")
ADB = os.environ.get("CZYTAJ_ADB", "/data/data/com.termux/files/usr/bin/adb")

# INSTANT path: the Voice Typer accessibility service writes this flag the moment a
# volume key is pressed (see thoughts/shared/petla/czytaj-volume-keys-CONTRACT.md),
# bypassing the ~3s Shizuku/adb key-DELIVERY floor that the evdev reader below is
# stuck with. One line "up <ms>" / "down <ms>"; the ms timestamp is unique per press
# so the poller tells a NEW press from a stale flag. VERIFIED on-device: accessibility
# onKeyEvent fires even with the SCREEN OFF, so this path covers all cases.
KEYTRIGGER_FLAG = os.environ.get(
    "CZYTAJ_KEYTRIGGER_FLAG",
    "/storage/emulated/0/Download/Termux-flags/czytaj-keytrigger.flag",
)
KEYTRIGGER_POLL_S = 0.08      # how often to poll the trigger flag (~instant, negligible cost)
FLAG_ECHO_WINDOW_S = 20.0     # (evdev fallback only) suppression window for the echo of an
                             # accessibility press — unreliable here, hence evdev is off by default.
# The evdev/Shizuku reader was the original key path, but delivery is slow (~3-11s) and
# flaky, and its DELAYED echo of an accessibility press double-fired the action (read the
# last message, then a beat later scrubbed to the 2nd-last). Suppressing that echo proved
# unreliable in this runtime (FUSE file mtimes stale; in-memory flags not seen across the
# poller/evdev threads). Since accessibility covers screen-on AND screen-off, the evdev
# reader is OFF by default; set CZYTAJ_EVDEV_FALLBACK=1 to re-enable it (e.g. if the
# accessibility service can't be granted) — accepting that its echo may double-fire.
EVDEV_FALLBACK = os.environ.get("CZYTAJ_EVDEV_FALLBACK", "0") == "1"

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
# FS3: filesystem mirror of _paused. The UPS hook removes this on every new prompt, so the
# watcher's in-memory _paused (which goes stale when a new turn stops+restarts the player)
# is re-synced across processes — the first VolumeDown after a new turn then PAUSES the
# fresh audio instead of sending a resume to nothing.
KEYPAUSE_STATE = os.path.expanduser("~/.claude/czytaj-keypause.state")

# Read-back counter: VolumeUp reads the last message; pressed again while a read is
# still playing it steps one message further back (2=previous, 3=older, …). Resets to
# the last message once playback has finished (idle) before the next press.
_readback_n = 0
_last_read_ts = 0.0
READBACK_WINDOW_S = 5.0   # rapid-tap window for scrubbing further back. Short now that the
                          # accessibility path delivers presses INSTANTLY (the old 45s was for
                          # the slow ~10-40s relay and made SEPARATE presses chain into a scrub,
                          # so a single press read the 3rd-from-last). Scrub ALSO triggers while a
                          # read is still playing (is_readback_playing). Reset to 1 on VolumeDown.


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
    # FS3: if we believe we're paused but the cross-process marker is gone, a new turn
    # restarted the player since our pause → treat as NOT paused so this press PAUSES the
    # fresh audio. (Contract: VolumeDown pauses the CURRENT clip only; it does NOT mute
    # future turns — use /pauza for a timed mute. FS6: intentional, documented here.)
    if _paused and not os.path.exists(KEYPAUSE_STATE):
        _paused = False
    if _paused:
        _media("play")
        _paused = False
        try:
            os.unlink(KEYPAUSE_STATE)
        except OSError:
            pass
        _log("VOLKEY", "resume")
    else:
        _media("pause")
        _paused = True
        try:
            open(KEYPAUSE_STATE, "w").close()
        except OSError:
            pass
        _log("VOLKEY", "pause")


def _read_back() -> None:
    """VolumeUp: read the LAST message. Step one further back (scrub) only when the user
    is clearly continuing — either a read-back is still PLAYING (pressed while listening)
    OR this press follows the last within READBACK_WINDOW_S (rapid taps). Otherwise reset
    to the last message. is_readback_playing() polls our own child (no slow media query)."""
    global _paused, _readback_n, _last_read_ts
    _paused = False
    try:
        os.unlink(KEYPAUSE_STATE)   # FS3: reading clears the pause-state marker (no longer paused)
    except OSError:
        pass
    now = time.monotonic()
    scrub = is_readback_playing() or (now - _last_read_ts) < READBACK_WINDOW_S
    _readback_n = _readback_n + 1 if scrub else 1
    _last_read_ts = now
    _log("VOLKEY", "VolumeUp -> read-back", _readback_n, "scrub" if scrub else "fresh")
    try:
        read_message_back(_readback_n)
    except Exception as e:  # never let one bad action kill the watcher
        _log("VOLKEY", "read-back-error", repr(e))


# Shared dispatch for BOTH input paths (evdev reader + accessibility trigger flag).
# A module-level debounce makes the SAME physical press act once even if both paths
# deliver it. The evdev path also stands down while the accessibility flag was written
# recently (`_flag_recent`) — its echo of that same press arrives seconds late and would
# double-fire. NB: that liveness check reads the flag FILE's mtime, NOT an in-memory flag.
# A bool set by the poller thread was observed NOT to be visible to the evdev thread in
# this runtime (while `_paused` was), so the filesystem is the reliable shared channel.
_dispatch_lock = threading.Lock()
_last_fire: "dict[int, float]" = {}


def _flag_recent() -> bool:
    """True iff the accessibility trigger flag (or its .tmp) was written within
    FLAG_ECHO_WINDOW_S — i.e. the accessibility path is live and a concurrent evdev event
    is just its slow echo. Filesystem-based (file mtime) so it is reliable across the
    poller thread and the evdev thread."""
    now = time.time()
    for p in (KEYTRIGGER_FLAG, KEYTRIGGER_FLAG + ".tmp"):
        try:
            if now - os.path.getmtime(p) < FLAG_ECHO_WINDOW_S:
                return True
        except OSError:
            pass
    return False


def _dispatch_key(code: int, *, trusted_fg: bool) -> None:
    """Act on one volume-key press. `trusted_fg=True` (accessibility flag path) skips
    the ~1.8s foreground check — the service already gated on Termux-foreground before
    writing the flag, and that skip is what keeps the flag path INSTANT. The evdev path
    (`trusted_fg=False`) is a FALLBACK for when the accessibility service isn't granted:
    while the flag was written recently (`_flag_recent`) the evdev reader stands down so
    its slow echo can't double-fire the action."""
    if code not in (KEY_VOLUMEDOWN, KEY_VOLUMEUP):
        return
    if not trusted_fg:
        if _flag_recent():
            _log("VOLKEY", "evdev-standdown (accessibility live)")
            return  # accessibility handled this press; we're just its slow echo
        if not _termux_foreground():
            return  # Termux not focused → leave the keys to their normal volume job
        _log("VOLKEY", "evdev-act (fallback; no recent accessibility flag)")
    with _dispatch_lock:
        now = time.monotonic()
        if now - _last_fire.get(code, 0.0) < DEBOUNCE_S:
            return
        _last_fire[code] = now
    # FS1: run the (slow ~3-9s) action in a DETACHED thread so the poller/evdev reader
    # returns IMMEDIATELY to detect the NEXT press. Inline, a 2nd/3rd VolumeUp arriving
    # during the 1st read was dropped (the poller was blocked inside read_message_back).
    # Safe: the debounce above already deduped THIS press, and _stop_previous_readback()
    # inside read_message_back interrupts the prior child so a fresh tap scrubs one further
    # back rather than overlapping — correct at human tap speed (> DEBOUNCE_S apart).
    _action = _toggle_pause if code == KEY_VOLUMEDOWN else _read_back
    threading.Thread(target=_action, daemon=True).start()


def _parse_keytrigger(path: str) -> "tuple[str, str] | None":
    """Parse one trigger file into (key, ts), or None when absent/empty/garbage.
    `key` is 'up'/'down'; `ts` is the app's per-press millis token used to dedup."""
    try:
        with open(path) as f:
            line = f.readline().strip()
    except OSError:
        return None
    if not line:
        return None
    parts = line.split()
    key = parts[0].lower()
    if key not in ("up", "down"):
        return None
    ts = parts[1] if len(parts) > 1 else line  # tolerate a no-timestamp flag (can't dedup)
    return key, ts


def _read_keytrigger() -> "tuple[str, str] | None":
    """Most-recent press as (key, ts). The app writes czytaj-keytrigger.flag atomically
    (temp + rename), but Android's File.renameTo can FAIL on emulated/FUSE shared
    storage — leaving the valid content orphaned in the .tmp (observed on-device). So
    read BOTH the final flag and its .tmp and return whichever carries the newer ts;
    ts-dedup in the poller makes reading the same press from either file idempotent."""
    cands = []
    for p in (KEYTRIGGER_FLAG, KEYTRIGGER_FLAG + ".tmp"):
        r = _parse_keytrigger(p)
        if r:
            cands.append(r)
    if not cands:
        return None

    def _newest(rt: "tuple[str, str]"):
        try:
            return (1, int(rt[1]))   # numeric millis → compare as numbers
        except (ValueError, TypeError):
            return (0, rt[1])        # non-numeric token → lexical fallback
    return max(cands, key=_newest)


def _poll_keytrigger() -> None:
    """Daemon loop: watch the accessibility-written trigger flag and dispatch the
    instant the app reports a press. Diffs the per-press timestamp so each physical
    press fires once; seeds from the current flag at startup so a stale flag left by a
    previous session doesn't fire on launch. This is the path that removes the ~3s
    key-delivery floor while the screen is ON."""
    seen = None
    cur = _read_keytrigger()
    if cur:
        seen = cur[1]  # whatever is there at startup counts as already handled
    while True:
        time.sleep(KEYTRIGGER_POLL_S)
        cur = _read_keytrigger()
        if not cur:
            continue
        key, ts = cur
        if ts == seen:
            continue  # no new press
        seen = ts
        # the app's write already refreshed the flag's mtime → evdev sees it via
        # _flag_recent() and stands down (filesystem is the reliable cross-thread channel).
        code = KEY_VOLUMEUP if key == "up" else KEY_VOLUMEDOWN
        _log("VOLKEY", "keytrigger", key)
        _dispatch_key(code, trusted_fg=True)


def _adb_serial() -> str:
    """Serial of a live adb device for the LOW-LATENCY reader path (a direct adb
    connection, no Shizuku relay → no ~11s rish floor). '' when adb isn't connected,
    so the caller falls back to rish (e.g. no Wi-Fi in the car). Only a device showing
    'device' (authorised) counts — 'offline'/'unauthorized' are ignored."""
    try:
        out = subprocess.run([ADB, "devices"], capture_output=True, text=True,
                             timeout=4).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].strip() == "device":
            return parts[0].strip()
    return ""


def _stream(device: str) -> None:
    """Read raw input_event structs from `device` and dispatch volume-key presses.
    PREFERS adb exec-out (a direct connection — raw write() per event, NO Shizuku
    relay, so a press arrives at once instead of the ~11s rish floor) when an adb
    device is connected; FALLS BACK to rish/Shizuku when adb is down (no Wi-Fi).
    Returns when the reader exits OR after READER_IDLE_RESTART_S of silence."""
    dev = device or "/dev/input/event0"
    serial = _adb_serial()
    if serial:
        cmd = [ADB, "-s", serial, "exec-out", f"dd if={dev} bs={_EV_SIZE} 2>/dev/null"]
    else:
        cmd = ["rish", "-c", f"dd if={dev} bs={_EV_SIZE} 2>/dev/null"]
    _log("VOLKEY", "reader via", "adb" if serial else "rish", dev)
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, bufsize=0)
    except (FileNotFoundError, OSError) as e:
        _log("VOLKEY", "reader-spawn-fail", repr(e))
        return
    buf = b""
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
                # Shared dispatch: foreground gate + debounce + dedup against the instant
                # accessibility flag path (evdev stands down while flags are flowing). The
                # keys are a GLOBAL remote — read-back/pause work whenever Termux is focused,
                # independent of czytaj on/off (on/off gates only AUTO-reading).
                _dispatch_key(code, trusted_fg=False)
    except OSError:
        pass
    finally:
        try:
            proc.kill()
            proc.wait(timeout=2)   # reap the dd child so it doesn't pile up as <defunct>
        except (OSError, subprocess.TimeoutExpired):
            pass


def _on_sigterm(signum, frame):
    # Turn a SIGTERM (toggle.sh teardown) into a clean exit so the finally blocks run:
    # _stream's finally kills the reader, main()'s finally releases the wakelock — else a
    # bare SIGTERM would skip them and leave the CPU pinned awake (battery drain).
    raise SystemExit(0)


def main() -> int:
    lock_fd = _single_instance()
    if lock_fd is None:
        return 0  # another watcher already owns the lock
    signal.signal(signal.SIGTERM, _on_sigterm)
    _log("VOLKEY", "watcher start pid=", os.getpid())
    # PRIMARY path: poll the accessibility trigger flag in a daemon thread. The Voice Typer
    # service delivers presses here at ~0ms (verified screen-on AND screen-off), so this is
    # the sole key path by default. Daemon so teardown (SIGTERM/lock release) isn't blocked.
    threading.Thread(target=_poll_keytrigger, name="keytrigger", daemon=True).start()
    if not EVDEV_FALLBACK:
        _log("VOLKEY", "evdev reader DISABLED — accessibility is the sole key path")
    # Clear a wakelock a previously-crashed watcher may have left held (SIGKILL skips finally).
    try:
        subprocess.run(["termux-wake-unlock"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=4)
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass
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
            if not EVDEV_FALLBACK:
                # accessibility poller (daemon thread) handles keys; the main loop just
                # keeps the wakelock fresh so the device can't doze and freeze the poller.
                time.sleep(IDLE_RECHECK_S)
                continue
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
