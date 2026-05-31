#!/usr/bin/env python3
"""czytaj volume-key watcher.

Reads raw kernel key events via Shizuku (`rish -c "getevent -l <device>"`) and
maps the hardware volume keys to czytaj actions while reading mode is ON:

    Volume Down  -> stop the current TTS playback immediately   (stop_now)
    Volume Up    -> re-read the active session's last message    (read_last_message)

Why getevent: Termux swallows the volume keys as terminal modifiers, so they
can't be bound inside Termux itself. Shizuku's shell-uid `getevent` reads the
raw kernel event stream globally, independent of who has focus — so the keys
work even mid-turn while Claude is generating.

getevent is PASSIVE: the keys still change system volume (consuming them would
need EVIOCGRAB, which would block volume control entirely). We only ACT on the
press, and only while at least one project has reading ON, so volume control is
never hijacked when czytaj is idle.

Resilience:
  * single-instance via an exclusive flock (toggle.sh spawns one per ON);
  * if rish/getevent exits (Shizuku service restart, input suspend on deep
    sleep, ...), the reader loop backs off and respawns;
  * the volume-key input device is auto-discovered (gpio_keys) and re-discovered
    on every respawn, so a post-reboot event-node renumber self-heals;
  * if discovery fails, falls back to reading ALL input devices (works, just
    noisier) so the feature degrades instead of dying.

Lifecycle: spawned by toggle.sh on the first project turning reading ON; killed
by toggle.sh when the last project turns reading OFF. The reading-ON gate inside
each dispatch is the safety net for the brief window before that pkill lands.
"""
from __future__ import annotations

import fcntl
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _speak import _log, stop_now, read_last_message  # noqa: E402

FLAG_DIR = os.path.expanduser("~/.claude/czytaj-flags")
SHIZUKU_FLAG = os.path.expanduser("~/.claude/czytaj-shizuku.flag")
LOCK_FILE = os.path.expanduser("~/.claude/czytaj-volume-watcher.lock")

# Label tokens emitted by `getevent -l` for the two keys we care about.
KEY_DOWN_LABEL = "KEY_VOLUMEDOWN"
KEY_UP_LABEL = "KEY_VOLUMEUP"
# `getevent -l` prints the value as DOWN/UP for 1/0; a held-key autorepeat shows
# the raw number (we ignore those — only the initial press should fire).
PRESS_VALUES = ("DOWN", "00000001", "1")

DEBOUNCE_S = 0.4          # ignore a repeat of the same key within this window
RESPAWN_DELAY_S = 3.0     # back-off after the getevent reader exits
IDLE_RECHECK_S = 5.0      # poll interval while Shizuku/rish is unavailable
# Optional override: CZYTAJ_VOLUME_DEVICE=/dev/input/eventN, or "all" for every device.
DEVICE_ENV = "CZYTAJ_VOLUME_DEVICE"


def _reading_on() -> bool:
    """True iff at least one project currently has reading mode ON."""
    try:
        with os.scandir(FLAG_DIR) as it:
            return any(True for _ in it)
    except OSError:
        return False


def _shizuku_ready() -> bool:
    return os.path.isfile(SHIZUKU_FLAG)


def _single_instance() -> "int | None":
    """Hold an exclusive lock so only one watcher runs. Returns the held fd
    (keep it open for the process lifetime) or None if another instance owns it."""
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
    """Return the /dev/input/eventN that exposes the volume keys (gpio_keys),
    or '' when it can't be determined (caller then reads all devices).

    The capability scan is done on the Android side with awk so only the single
    device path crosses the rish relay — multi-line rish output proved flaky and
    intermittently truncated. Retried a few times because `getevent -lp` over
    Shizuku occasionally comes back empty under contention."""
    override = os.environ.get(DEVICE_ENV, "").strip()
    if override:
        return "" if override == "all" else override
    script = (
        "getevent -lp 2>/dev/null | "
        "awk '/^add device/{d=$4} /KEY_VOLUMEUP/{print d; exit}'"
    )
    for _ in range(3):
        try:
            out = subprocess.run(
                ["rish", "-c", script],
                capture_output=True, text=True, timeout=15,
            ).stdout.strip()
        except (subprocess.SubprocessError, FileNotFoundError, OSError):
            out = ""
        if out:
            return out.splitlines()[0].strip()
        time.sleep(0.5)
    return ""


def _press_label(line: str) -> "str | None":
    """Return KEY_VOLUMEDOWN / KEY_VOLUMEUP when `line` is a getevent PRESS event
    for that key, else None. Handles both device-prefixed lines (all-device mode,
    e.g. "/dev/input/event0: EV_KEY KEY_VOLUMEDOWN DOWN") and bare lines
    (single-device mode, e.g. "EV_KEY KEY_VOLUMEUP DOWN"). The value token is
    checked explicitly so a RELEASE line ("KEY_VOLUMEDOWN UP") isn't mistaken for
    a press just because the substring "DOWN" appears in the key name."""
    if "KEY_VOLUME" not in line:
        return None
    parts = line.split()
    if len(parts) < 2:
        return None
    label, value = parts[-2], parts[-1]
    if value not in PRESS_VALUES:
        return None  # release or held-key autorepeat
    if label not in (KEY_DOWN_LABEL, KEY_UP_LABEL):
        return None
    return label


def _dispatch(label: str) -> None:
    if label == KEY_DOWN_LABEL:
        _log("VOLKEY", "VolumeDown -> stop")
        try:
            stop_now()
        except Exception as e:  # never let one bad press kill the watcher
            _log("VOLKEY", "stop-error", repr(e))
    elif label == KEY_UP_LABEL:
        _log("VOLKEY", "VolumeUp -> read-last")
        try:
            read_last_message()
        except Exception as e:
            _log("VOLKEY", "read-last-error", repr(e))


def _stream(device: str) -> None:
    """Run getevent (via rish) for `device` (or all devices when '') and
    dispatch volume-key presses until the reader exits."""
    cmd = ["rish", "-c", "getevent -l" + (f" {device}" if device else "")]
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )  # binary stdout: readline returns each line as the kernel emits it
    except (FileNotFoundError, OSError) as e:
        _log("VOLKEY", "getevent-spawn-fail", repr(e))
        return
    last_fire: dict[str, float] = {}
    try:
        assert proc.stdout is not None
        for raw in iter(proc.stdout.readline, b""):
            line = raw.decode("utf-8", errors="replace")
            label = _press_label(line)
            if label is None:
                continue
            if not _reading_on():
                continue  # never act on volume keys while reading is OFF
            now = time.monotonic()
            if now - last_fire.get(label, 0.0) < DEBOUNCE_S:
                continue
            last_fire[label] = now
            _dispatch(label)
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
    try:
        while True:
            if not _shizuku_ready():
                time.sleep(IDLE_RECHECK_S)
                continue
            device = _discover_volume_device()
            _log("VOLKEY", "reading", device or "ALL-devices")
            _stream(device)
            # reader returned -> getevent/rish exited; back off then respawn.
            time.sleep(RESPAWN_DELAY_S)
    finally:
        _log("VOLKEY", "watcher exit")
        try:
            os.close(lock_fd)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
