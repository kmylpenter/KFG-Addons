#!/usr/bin/env python3
"""Piper neural TTS streaming client.

Reads text from stdin, asks the Piper server (via UNIX socket) to synthesize
straight into a FIFO that paplay is already reading from. This gives
near-real-time playback without intermediate WAV conversion.

Falls back to a one-shot synthesize() of the bundled `piper` binary if the
server is unavailable (e.g. during install before daemon comes up).
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile
import threading
import time
import wave
from pathlib import Path

PIPER_HOME = Path(os.environ.get("PIPER_HOME", str(Path.home() / "piper-tts")))
PIPER_BIN = PIPER_HOME / "piper1-gpl" / "libpiper" / "piper"
PIPER_LIB = PIPER_HOME / "piper1-gpl" / "libpiper" / "install" / "lib"
PIPER_ESPEAK = PIPER_HOME / "piper1-gpl" / "libpiper" / "install" / "espeak-ng-data"
PIPER_VOICES = PIPER_HOME / "voices"
PIPER_VOICE = os.environ.get("PIPER_VOICE", "pl_PL-gosia-medium")
try:
    PIPER_SAMPLE_RATE = int(os.environ.get("PIPER_SAMPLE_RATE", "22050"))
except ValueError:
    PIPER_SAMPLE_RATE = 22050
VOICE_TYPER_FLAG = os.path.expanduser(
    "~/storage/downloads/Termux-flags/voice-typer-recording.flag"
)
PREHEAT_WAV = Path(os.path.dirname(os.path.abspath(__file__))) / "preheat.wav"
SILENT_WAV = Path(os.path.dirname(os.path.abspath(__file__))) / "silent.wav"


PREHEAT_MARKER = Path(os.path.expanduser("~/.claude/czytaj-preheat.ts"))
PREHEAT_VALID_S = 60


def unlock_audio_routing() -> None:
    """Spotify-style audio routing unlock for Android Auto / Bluetooth.
    Plays an audible ~0.8s 80Hz tone via termux-media-player to wake Android
    MediaSession routing. Cached: skip if already done within last 60s
    (prevents preheat queue stacking when many hooks fire in quick succession).
    Also runs `stop` first to clear any leftover queued playback."""
    try:
        last = PREHEAT_MARKER.stat().st_mtime
        if time.time() - last < PREHEAT_VALID_S:
            return
    except OSError:
        pass
    tone = PREHEAT_WAV if PREHEAT_WAV.is_file() else SILENT_WAV
    if not tone.is_file():
        return
    try:
        subprocess.run(
            ["termux-media-player", "stop"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    try:
        subprocess.Popen(
            ["termux-media-player", "play", str(tone)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        time.sleep(0.9)
        try:
            PREHEAT_MARKER.touch()
        except OSError:
            pass
    except FileNotFoundError:
        pass


def watch_and_kill(proc: subprocess.Popen, fifo: Path | None,
                   stop_event: threading.Event) -> None:
    """Kill paplay (and unlink FIFO so the daemon's pending write fails fast
    with EPIPE) the moment Voice Typer starts recording."""
    while not stop_event.is_set():
        if proc.poll() is not None:
            return
        if os.path.isfile(VOICE_TYPER_FLAG):
            try:
                proc.kill()
            except ProcessLookupError:
                pass
            if fifo is not None:
                try:
                    fifo.unlink()
                except OSError:
                    pass
            return
        stop_event.wait(0.15)


def synthesize_one_shot(text: str, out_wav: Path) -> bool:
    """Run the bundled `piper` CLI directly. Used only when the server is
    unavailable (fallback path)."""
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{PIPER_LIB}:{env.get('LD_LIBRARY_PATH', '')}"
    env["ESPEAK_DATA_PATH"] = str(PIPER_ESPEAK)
    env["PIPER_VOICE_PATH"] = str(PIPER_VOICES)
    env["PIPER_LENGTH_SCALE"] = os.environ.get("PIPER_LENGTH_SCALE", "0.6")
    raw_path = out_wav.with_suffix(".raw")
    try:
        proc = subprocess.run(
            [str(PIPER_BIN), "-m", PIPER_VOICE, "-f", str(raw_path)],
            input=text.encode("utf-8"),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
        if proc.returncode != 0 or not raw_path.exists():
            return False
        with open(raw_path, "rb") as f:
            raw = f.read()
        n = len(raw) // 4
        if n == 0:
            return False
        floats = struct.unpack(f"<{n}f", raw)
        shorts = struct.pack(
            f"<{n}h",
            *(max(-32767, min(32767, int(x * 32767))) for x in floats),
        )
        with wave.open(str(out_wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(PIPER_SAMPLE_RATE)
            w.writeframes(shorts)
        return True
    except (subprocess.TimeoutExpired, OSError):
        return False
    finally:
        try:
            raw_path.unlink()
        except OSError:
            pass


def play_blocking(audio: Path, raw_rate: int | None = None) -> None:
    """Block until paplay finishes. raw_rate is set when audio is raw float32."""
    try:
        if raw_rate:
            subprocess.run(
                [
                    "paplay", "--raw",
                    f"--rate={raw_rate}",
                    "--channels=1",
                    "--format=float32le",
                    str(audio),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=120,
            )
        else:
            subprocess.run(
                ["paplay", str(audio)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=120,
            )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return


def _log(*parts: object) -> None:
    try:
        with open(os.path.expanduser("~/.claude/czytaj.log"), "a") as f:
            ts = time.strftime("%H:%M:%S")
            f.write(f"{ts} pid={os.getpid()} STREAM {' '.join(str(p) for p in parts)}\n")
    except OSError:
        pass


def main() -> int:
    text = sys.stdin.read().strip()
    if not text:
        _log("EXIT empty-text")
        return 0
    _log("ENTER len=", len(text), "first40=", repr(text[:40]))

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        from piper_server import speak_raw as server_speak_raw, ensure_running
    except ImportError:
        server_speak_raw = None
        ensure_running = None

    with tempfile.TemporaryDirectory(prefix="piper-single-") as td:
        if server_speak_raw is not None and ensure_running is not None and ensure_running():
            fifo = Path(td) / "stream.fifo"
            try:
                os.mkfifo(str(fifo))
            except OSError:
                fifo = None
            if fifo is not None:
                unlock_audio_routing()
                paplay = subprocess.Popen(
                    [
                        "paplay", "--raw",
                        f"--rate={PIPER_SAMPLE_RATE}",
                        "--channels=1",
                        "--format=float32le",
                        "--latency-msec=50",
                        str(fifo),
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                stop_event = threading.Event()
                watcher = threading.Thread(
                    target=watch_and_kill, args=(paplay, fifo, stop_event), daemon=True
                )
                watcher.start()
                got_rate = None
                try:
                    got_rate = server_speak_raw(text, fifo)
                finally:
                    if not got_rate:
                        try:
                            with open(str(fifo), "wb"):
                                pass
                        except OSError:
                            pass
                    try:
                        paplay.wait(timeout=120)
                    except subprocess.TimeoutExpired:
                        try:
                            paplay.kill()
                        except ProcessLookupError:
                            pass
                        try:
                            paplay.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            pass
                    stop_event.set()
                    watcher.join(timeout=1)
                if got_rate:
                    return 0

        if server_speak_raw is not None and ensure_running is not None:
            out = Path(td) / "out.raw"
            rate = server_speak_raw(text, out)
            if rate:
                unlock_audio_routing()
                play_blocking(out, raw_rate=rate)
                return 0

        if not PIPER_BIN.exists():
            return 2
        wav = Path(td) / "out.wav"
        if synthesize_one_shot(text, wav):
            unlock_audio_routing()
            play_blocking(wav)
            return 0
        return 1


if __name__ == "__main__":
    sys.exit(main())
