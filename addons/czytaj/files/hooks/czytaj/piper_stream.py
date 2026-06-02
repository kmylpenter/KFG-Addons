#!/usr/bin/env python3
"""Piper neural TTS streaming client.

Reads text from stdin, asks the Piper server (via UNIX socket) to synthesize
straight into a FIFO that paplay is already reading from. This gives
near-real-time playback without intermediate WAV conversion.

Falls back to a one-shot synthesize() of the bundled `piper` binary if the
server is unavailable (e.g. during install before daemon comes up).
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import time
import wave
from pathlib import Path

def _resolve_piper_home() -> Path:
    """Locate the piper-tts install. Order: $PIPER_HOME, then ~/piper-tts,
    then the old Termux home (piper may have been built under
    /data/data/com.termux/files/home before a native/PRoot switch moved HOME
    to /root). First layout that actually contains the binary wins."""
    env = os.environ.get("PIPER_HOME")
    if env:
        return Path(env)
    for home in (Path.home() / "piper-tts",
                 Path("/data/data/com.termux/files/home/piper-tts")):
        if (home / "piper1-gpl" / "libpiper" / "piper").exists():
            return home
    return Path.home() / "piper-tts"


PIPER_HOME = _resolve_piper_home()
PIPER_BIN = PIPER_HOME / "piper1-gpl" / "libpiper" / "piper"
PIPER_LIB = PIPER_HOME / "piper1-gpl" / "libpiper" / "install" / "lib"
PIPER_ESPEAK = PIPER_HOME / "piper1-gpl" / "libpiper" / "install" / "espeak-ng-data"
PIPER_VOICES = PIPER_HOME / "voices"
PIPER_VOICE = os.environ.get("PIPER_VOICE", "pl_PL-gosia-medium")
try:
    PIPER_SAMPLE_RATE = int(os.environ.get("PIPER_SAMPLE_RATE", "22050"))
except ValueError:
    PIPER_SAMPLE_RATE = 22050
def _resolve_voice_typer_flag() -> str:
    """First home whose Termux-flags dir exists. On native PRoot ~/storage is
    absent (HOME=/root), so the flag lives under the Termux home — otherwise
    dictation can't interrupt playback."""
    rel = "storage/downloads/Termux-flags/voice-typer-recording.flag"
    for home in (os.path.expanduser("~"),
                 "/data/data/com.termux/files/home"):
        cand = os.path.join(home, rel)
        if os.path.isdir(os.path.dirname(cand)):
            return cand
    return os.path.expanduser("~/" + rel)


VOICE_TYPER_FLAG = _resolve_voice_typer_flag()
VOICE_TYPER_STALE_S = 3.0  # keyboard heartbeats ≤1s (F10/F27 — mirror of _speak.py)


def _vt_recording() -> bool:
    """Voice Typer dictating? Honours the heartbeat-timestamp staleness like
    _speak.is_recording (F27 — kept in sync). Empty/odd flag → treat as recording."""
    try:
        with open(VOICE_TYPER_FLAG) as fh:
            content = fh.read().strip()
    except OSError:
        return False
    if not content:
        return True
    try:
        ts = float(content)
    except ValueError:
        return True
    return (time.time() - ts) <= VOICE_TYPER_STALE_S


_LENGTH_ENSURED = False


def _ensure_voice_length_scale() -> None:
    """F9 (real fix): the piper1-gpl binary has NO --length-scale flag and IGNORES
    the PIPER_LENGTH_SCALE env var — it reads length_scale from the voice's
    .onnx.json. So set inference.length_scale to PIPER_LENGTH_SCALE (default 0.6)
    idempotently, once per process; self-heals if the voice is ever re-downloaded.
    Best-effort: any error leaves the config untouched and never blocks synth."""
    global _LENGTH_ENSURED
    if _LENGTH_ENSURED:
        return
    _LENGTH_ENSURED = True
    try:
        target = float(os.environ.get("PIPER_LENGTH_SCALE", "0.6"))
        cfg = PIPER_VOICES / f"{PIPER_VOICE}.onnx.json"
        with open(cfg) as fh:
            d = json.load(fh)
        inf = d.get("inference") or {}
        if abs(float(inf.get("length_scale", 1)) - target) > 1e-6:
            inf["length_scale"] = target
            d["inference"] = inf
            tmp = str(cfg) + ".tmp"
            with open(tmp, "w") as fh:
                json.dump(d, fh)
            os.replace(tmp, cfg)
    except Exception:
        pass


PREHEAT_WAV = Path(os.path.dirname(os.path.abspath(__file__))) / "preheat.wav"
SILENT_WAV = Path(os.path.dirname(os.path.abspath(__file__))) / "silent.wav"


PREHEAT_MARKER = Path(os.path.expanduser("~/.claude/czytaj-preheat.ts"))
PREHEAT_VALID_S = 60


def _audio_scratch_dir() -> Path | None:
    """Directory for wavs that termux-media-player (the Android media app,
    running OUTSIDE PRoot) can actually open. PRoot paths like /tmp and /root
    are INVISIBLE to it — that was the silent-TTS bug on the native install:
    piper wrote into a PRoot tempdir and the player got ENOENT. Stage audio
    under the Termux-shared tree instead. Falls back to the system temp only
    as a last resort (fine when paplay, which lives inside PRoot, is the
    backend)."""
    for d in (Path("/data/data/com.termux/files/home/.cache/czytaj"),
              Path("/data/data/com.termux/files/usr/tmp")):
        try:
            d.mkdir(parents=True, exist_ok=True)
            probe = d / ".wtest"
            probe.write_text("x")
            probe.unlink()
            return d
        except OSError:
            continue
    # F11: NO gettempdir fallback — both callers (native mkstemp + _staged_tone)
    # feed termux-media-player, which can't read a PRoot tempdir (ENOENT → silent
    # TTS). Return None so callers fail loudly instead of staging unplayably.
    return None


def _staged_tone() -> Path | None:
    """The preheat/silence tone on a path the Android player can read. The
    bundled wavs live inside PRoot (~/.claude/hooks/czytaj/), invisible to
    termux-media-player, so copy once into the shared audio dir."""
    src = PREHEAT_WAV if PREHEAT_WAV.is_file() else SILENT_WAV
    if not src.is_file():
        return None
    d = _audio_scratch_dir()
    if d is None:
        return None  # F11: no Android-readable dir → skip preheat (never stage a PRoot path)
    try:
        dst = d / src.name
        if not dst.exists() or dst.stat().st_size != src.stat().st_size:
            import shutil
            shutil.copy2(src, dst)
        return dst
    except OSError:
        return None  # F11: was `return src` (a PRoot path the player can't open → ENOENT)


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
    tone = _staged_tone()  # shared-readable copy; PRoot paths are invisible to the player
    if tone is None or not tone.is_file():
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
        if _vt_recording():  # F10/F27: heartbeat-aware, not bare presence
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
        _ensure_voice_length_scale()  # F9: tempo lives in the voice .onnx.json
        proc = subprocess.run(
            [str(PIPER_BIN), "-m", PIPER_VOICE, "-f", str(raw_path)],
            input=text.encode("utf-8"),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        if proc.returncode != 0 or not raw_path.exists():
            _log("SYNTH-FAIL rc=", proc.returncode, "stderr=",
                 (proc.stderr or b"").decode("utf-8", "replace")[-200:])
            return False
        with open(raw_path, "rb") as f:
            raw = f.read()
        n = len(raw) // 4
        if n == 0:
            return False
        floats = struct.unpack(f"<{n}f", raw[:n * 4])   # slice: a truncated/odd tail must not raise struct.error
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
    except (subprocess.TimeoutExpired, OSError, struct.error) as exc:
        _log("SYNTH-FAIL exception:", exc)
        return False
    finally:
        try:
            raw_path.unlink()
        except OSError:
            pass


def synthesize_warm(text: str, out_wav: Path) -> bool:
    """Synthesise `text` to a playable 16-bit wav via the WARM piper daemon (model
    already loaded → ~0.7s, NO per-call cold start). The daemon emits raw float32, so
    convert it to wav exactly like synthesize_one_shot. Falls back to the cold one-shot
    binary if the daemon is unavailable — so callers always get a wav."""
    try:
        from piper_server import speak_raw, ensure_running
        if not ensure_running():
            return synthesize_one_shot(text, out_wav)
    except Exception:
        return synthesize_one_shot(text, out_wav)
    _ensure_voice_length_scale()   # F9: keep length_scale patched in the voice .onnx.json on
    #                                the WARM path too, else a re-downloaded voice loses the tempo fix
    raw_path = out_wav.with_suffix(".srv.raw")
    try:
        rate = speak_raw(text, raw_path)
    except Exception:
        rate = None
    try:
        if not rate or not raw_path.exists():
            return synthesize_one_shot(text, out_wav)
        with open(raw_path, "rb") as f:
            raw = f.read()
        n = len(raw) // 4
        if n == 0:
            return synthesize_one_shot(text, out_wav)
        floats = struct.unpack(f"<{n}f", raw[:n * 4])   # slice: a truncated/odd tail must not raise struct.error
        shorts = struct.pack(
            f"<{n}h",
            *(max(-32767, min(32767, int(x * 32767))) for x in floats),
        )
        with wave.open(str(out_wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(int(rate))
            w.writeframes(shorts)
        return True
    except Exception as exc:
        _log("WARM-SYNTH-FAIL", exc)
        return synthesize_one_shot(text, out_wav)
    finally:
        try:
            raw_path.unlink()
        except OSError:
            pass


def _pulse_available() -> bool:
    """Is a PulseAudio server reachable? The old Termux-app install had one;
    native PRoot/Debian has none (no pulse/ALSA/pipewire) — only the Termux:API
    bridge. `pactl info` returncode 0 = server up. Any failure -> unavailable."""
    try:
        r = subprocess.run(
            ["pactl", "info"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2,
        )
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _wav_duration_s(audio: Path) -> float:
    """Length of a wav in seconds; 0 on any error (best-effort poll bound)."""
    try:
        with wave.open(str(audio), "rb") as wf:
            rate = wf.getframerate() or PIPER_SAMPLE_RATE
            return wf.getnframes() / float(rate) if rate else 0.0
    except (wave.Error, OSError):
        return 0.0


def _play_via_termux_blocking(audio: Path) -> None:
    """Play a wav through termux-media-player (Termux:API -> Android
    MediaPlayer) and BLOCK until it finishes. This is the ONLY working route on
    native PRoot Debian and keeps playing with the screen off / phone locked.
    termux-media-player returns immediately, so poll `info` until not Playing
    (bounded by wav duration) to preserve the one-utterance-at-a-time contract
    and stop the caller from deleting the temp wav mid-playback. Raw float32
    can't be fed to MediaPlayer, so this path is wav-only."""
    try:
        subprocess.run(
            ["termux-media-player", "play", str(audio)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        # F13: don't swallow a missing/broken termux-media-player silently —
        # the Termux bridge is intermittently "command not found" on PRoot.
        _log("PLAY-FAIL termux-media-player:", exc)
        return
    # Pause-aware poll. VolumeDown pauses via termux-media-player, flipping `info`
    # to "Paused" — that must NOT read as "finished" (else we'd release the channel
    # + delete the wav, and resume would break). While paused we keep holding and
    # FREEZE the play-budget so a long pause can't trip the duration deadline; a
    # hard cap bounds a pause the user never resumes.
    play_budget = _wav_duration_s(audio) + 3.0
    hard_cap = time.monotonic() + 1800.0
    last = time.monotonic()
    time.sleep(0.3)  # let `info` flip to Playing before we poll
    while time.monotonic() < hard_cap:
        # Voice Typer started dictation → stop talking over the user at once.
        if _vt_recording():  # F10/F27: heartbeat-aware, not bare presence
            try:
                subprocess.run(
                    ["termux-media-player", "stop"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
                )
            except (OSError, subprocess.SubprocessError):
                pass
            break
        try:
            r = subprocess.run(
                ["termux-media-player", "info"],
                capture_output=True, text=True, timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            break
        out = r.stdout or ""
        now = time.monotonic()
        if "Paused" in out:
            last = now          # freeze the budget while paused (VolumeDown)
            time.sleep(0.3)
            continue
        if "Playing" not in out:
            break               # finished or stopped
        play_budget -= now - last
        last = now
        if play_budget <= 0:
            break
        time.sleep(0.3)


def play_blocking(audio: Path, raw_rate: int | None = None) -> None:
    """Block until playback finishes. Uses paplay when a PulseAudio server is
    up (old Termux-app install; supports the raw float32 stream path), else
    falls back to termux-media-player (native PRoot). The Termux path needs a
    real wav file — raw float32 isn't playable there, so raw_rate audio only
    plays when pulse is present."""
    if not _pulse_available():
        if raw_rate is None:
            _play_via_termux_blocking(audio)
        # raw float32 + no pulse: nothing can play it; caller's wav fallback
        # (synthesize_one_shot -> play_blocking(wav)) covers the native path.
        return
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


# ── F3/F6/F7: cross-window channel reservation (native single-player only) ──
# The native route shares ONE Android MediaPlayer across all windows, so a
# background pane's `play` would cut off the active pane. This advisory state
# (NOT a held lock — see audit RR-3) lets the active pane have priority and a
# background pane yield while the channel is busy. FAIL-OPEN: any uncertainty
# resolves to "play", so the worst case is the old behaviour, never silence.
CHANNEL_FILE = os.path.expanduser("~/.claude/czytaj-channel")
CHANNEL_STALE_S = 30.0  # a claim older than this is ignored (crashed/killed owner)


def _read_channel():
    """(end_ts, owner, priority, claim_ts) or None. None on any error (fail-open)."""
    try:
        with open(CHANNEL_FILE) as f:
            p = f.read().split()
        return float(p[0]), p[1], p[2], float(p[3])
    except (OSError, ValueError, IndexError):
        return None


def _write_channel(end_ts: float, owner: str, priority: str) -> None:
    tmp = CHANNEL_FILE + ".tmp"
    try:
        with open(tmp, "w") as f:
            f.write(f"{end_ts} {owner or 'pane'} {priority} {time.time()}")
        os.replace(tmp, CHANNEL_FILE)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def _reserve_channel(wav: Path) -> None:
    """Cross-window QUEUE on the shared single Android player: if ANOTHER window
    currently owns the channel, WAIT until its utterance ends, then claim+play — so
    two windows with czytaj on read one-after-another and never cut each other.
    The SAME window never waits (a newer utterance just replaces its own previous
    via termux-media-player's single-player play = latest-wins within a window).
    FAIL-OPEN: unreadable channel / 45s cap → play anyway (never block into silence)."""
    owner = os.environ.get("CZYTAJ_TID", "") or "pane"
    try:
        dur = _wav_duration_s(wav)
    except Exception:
        dur = 0.0
    dur = dur if dur > 0 else 8.0
    deadline = time.time() + 45.0   # hard cap so one window can't wedge another forever
    while time.time() < deadline:
        ch = _read_channel()
        if ch is None:
            break                                    # free
        c_end, c_owner, _c_prio, c_claim = ch
        now = time.time()
        if c_owner == owner or now >= c_end or (now - c_claim) > CHANNEL_STALE_S:
            break                                    # mine (replace) / expired / stale
        time.sleep(0.3)                              # ANOTHER window busy → queue (wait)
    _write_channel(time.time() + dur + 1.0, owner, "active")


def _prune_scratch(max_age_s: float = 120.0) -> None:
    """F34: remove tmp*.wav left in the scratch dir by a SIGKILL'd piper_stream
    (pkill -9 bypasses the finally-unlink). Only tmp*.wav — never the persistent
    preheat/silent tones."""
    d = _audio_scratch_dir()
    if d is None:
        return
    try:
        now = time.time()
        for pat in ("tmp*.wav", "*.raw", "*.srv.raw"):   # also reap raw intermediates a
            for p in d.glob(pat):                        # SIGKILL'd synth left behind
                try:
                    if now - p.stat().st_mtime > max_age_s:
                        p.unlink()
                except OSError:
                    pass
    except OSError:
        pass


def _play_cached_wav(path: str) -> int:
    """Play a PRE-SYNTHESISED wav (read-back CACHE HIT) — no synthesis, instant start.
    Reuses the normal playback path (pause-aware poll, Voice-Typer interrupt, cross-window
    channel reservation) but does NOT delete the file — it is the persistent read-back cache."""
    p = Path(path)
    if not p.is_file():
        _log("PLAYWAV-MISSING", path)
        return 3
    _log("PLAYWAV len=", p.stat().st_size, "name=", p.name)
    _prune_scratch()
    if not _pulse_available():
        _reserve_channel(p)   # cross-window QUEUE on the shared player (same as synth path)
    unlock_audio_routing()
    play_blocking(p)
    return 0


def main() -> int:
    # Read-back CACHE HIT: a pre-synthesised wav path is handed in via env — skip synth
    # entirely and just play it (instant). stdin is /dev/null in this mode.
    play_wav = os.environ.get("CZYTAJ_PLAY_WAV", "")
    if play_wav:
        return _play_cached_wav(play_wav)
    # F23: decode stdin explicitly as UTF-8 (the writer pins utf-8). sys.stdin.read()
    # uses the process locale and crashes on Polish diacritics under LANG=C/POSIX.
    # F31: collapse newlines like the daemon path so both synth routes are consistent.
    text = sys.stdin.buffer.read().decode("utf-8", "replace").replace("\n", " ").strip()
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

    # Audio backend: the server-FIFO + raw streaming paths both feed paplay,
    # which needs a PulseAudio server. Native PRoot/Debian has none, so when
    # pulse is absent skip straight to file synth + termux-media-player.
    pulse = _pulse_available()

    with tempfile.TemporaryDirectory(prefix="piper-single-") as td:
        if pulse and server_speak_raw is not None and ensure_running is not None and ensure_running():
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

        if pulse and server_speak_raw is not None and ensure_running is not None:
            out = Path(td) / "out.raw"
            rate = server_speak_raw(text, out)
            if rate:
                unlock_audio_routing()
                play_blocking(out, raw_rate=rate)
                return 0

        if not PIPER_BIN.exists():
            return 2
        # paplay (inside PRoot) can read PRoot paths, so the fast tempdir is
        # fine when pulse is up. termux-media-player (Android, outside PRoot)
        # CANNOT — on the native path the wav must live in the Termux-shared
        # tree or the player gets ENOENT and nothing is heard.
        if pulse:
            wav = Path(td) / "out.wav"
            if synthesize_one_shot(text, wav):
                unlock_audio_routing()
                play_blocking(wav)
                return 0
            return 1
        scratch = _audio_scratch_dir()
        if scratch is None:
            _log("EXIT no-android-readable-scratch")  # F11: don't stage a PRoot path
            return 3
        _prune_scratch()  # F34: clear tmp*.wav leaked by a SIGKILL'd prior run
        fd, name = tempfile.mkstemp(suffix=".wav", dir=str(scratch))
        os.close(fd)
        wav = Path(name)
        try:
            if synthesize_warm(text, wav):   # warm daemon (~0.7s) → wav; cold fallback inside
                # Cross-window QUEUE: wait here until no OTHER window owns the shared
                # player, then claim it. Same window / free channel → no wait.
                _reserve_channel(wav)
                unlock_audio_routing()
                play_blocking(wav)  # blocks until done, then we delete
                return 0
            return 1
        finally:
            try:
                wav.unlink()
            except OSError:
                pass


if __name__ == "__main__":
    sys.exit(main())
