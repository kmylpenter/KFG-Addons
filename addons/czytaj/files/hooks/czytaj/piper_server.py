#!/usr/bin/env python3
"""Long-lived Piper TTS server.

Spawns piper-daemon (C++) once with model preloaded, then listens on a UNIX
socket. Each client connection sends text and receives the path to a generated
WAV file. This eliminates the ~5s cold-start cost of loading the ONNX model
on every speak operation.

Auto-starts itself: clients call ensure_running() which double-forks the
server if no PID is alive.
"""
from __future__ import annotations

import errno
import fcntl
import json
import os
import signal
import socket
import select
import struct
import subprocess
import sys
import tempfile
import threading
import time
import wave
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import czytaj_paths as cz  # noqa: E402  — SSOT for paths/config (audit 2026-06-15)

# Piper install layout + daemon RUN_DIR + synth defaults now come from czytaj_paths.
# S2/S4/S5: RUN_DIR used to be hardcoded HERE and in toggle.sh and install.sh (kept aligned
# by a "MUST match" comment) — its earlier divergence split the daemon across processes so the
# socket was never shared and synth was ALWAYS cold (~3-7s); the piper-home resolver was
# copy-pasted across 3 files. Wrapped in Path() because this module uses the Path API.
# RUN_DIR MUST equal czytaj-env.sh's CZYTAJ_RUN_DIR — pinned by czytaj_selftest.py.
PIPER_HOME = Path(cz.PIPER_HOME)
PIPER_DAEMON = Path(cz.PIPER_DAEMON)
PIPER_LIB = Path(cz.PIPER_LIB)
PIPER_ESPEAK = Path(cz.PIPER_ESPEAK)
PIPER_VOICES = Path(cz.PIPER_VOICES)
FLAG_DIR = Path(cz.FLAG_DIR)   # F1: per-project flags dir
RUN_DIR = Path(cz.RUN_DIR)
SOCKET_PATH = Path(cz.SOCKET_PATH)
PID_FILE = Path(cz.PID_FILE)
LOCK_FILE = Path(cz.SERVER_LOCK)
DEFAULT_VOICE = cz.PIPER_VOICE
DEFAULT_LENGTH = cz.PIPER_LENGTH_SCALE
DEFAULT_SAMPLE_RATE = cz.PIPER_SAMPLE_RATE
SERVER_IDLE_TIMEOUT_S = int(os.environ.get("PIPER_IDLE_TIMEOUT", "1800"))
DAEMON_READ_TIMEOUT_S = float(os.environ.get("PIPER_DAEMON_TIMEOUT", "40"))  # 2026-06-15: was 10.
# SD1 set 10 assuming "a 2000-char read-back is a few seconds" — MEASURED WRONG on this device:
# 147 chars synth in ~2s, so a full ~2000-char read-back is ~27s, which the 10s cap KILLED
# mid-synth → cold fallback (~48s) AND the killed daemon left the next read cold too. 40s lets a
# full read-back finish on the WARM daemon (~27s) without dying. A genuinely hung daemon now stalls
# 40s, but server_alive()'s PING already catches a DEAD daemon before synth, so the only exposure
# is a mid-synth hang (rare). speak_raw's socket timeout stays above this so the server's own
# kill+respond fires first.
_daemon_err_count = 0  # FD4: consecutive synth-failure counter; recycle the daemon after 2 (below)


def _is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _ping(timeout: float = 0.3) -> bool:
    """Connect AND round-trip a {"ping":1} → {"ok":true}. A bare socket connect (the old
    _can_connect) passed even for a daemon that was bound but WEDGED, so server_alive would
    green-light a dead daemon and every synth silently took the ~3-7s cold path (audit S6).
    A real pong proves the accept loop is actually servicing requests."""
    if not SOCKET_PATH.exists():
        return False
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(SOCKET_PATH))
        s.sendall(b'{"ping":1}\n\n')
        data = b""
        while b"\n" not in data:
            chunk = s.recv(256)
            if not chunk:
                break
            data += chunk
        resp = json.loads(data.decode("utf-8", "ignore").strip() or "{}")
        return bool(resp.get("ok"))
    except (OSError, json.JSONDecodeError):
        return False
    finally:
        try:
            s.close()
        except OSError:
            pass


def server_alive() -> bool:
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text().strip())
    except (OSError, ValueError):
        return False
    if not _is_alive(pid):
        for p in (SOCKET_PATH, PID_FILE):
            try:
                p.unlink()
            except OSError:
                pass
        return False
    if not _ping():
        # F19/S6: PID alive but the daemon doesn't pong — socket unreachable (killed -9
        # mid-bind / stale socket) OR bound-but-wedged. Remove the stale socket so the next
        # ensure_running rebinds cleanly (recycling a wedged daemon) instead of a client
        # stalling on a dead path or silently falling back to a ~3-7s cold synth every call.
        try:
            SOCKET_PATH.unlink()
        except OSError:
            pass
        return False
    return True


def _flags_present() -> bool:
    """True if ANY project flag exists (czytaj ON somewhere). Exception-safe so a
    FLAG_DIR that vanishes mid-scandir can't crash the daemon loop (RG2)."""
    try:
        return FLAG_DIR.is_dir() and any(FLAG_DIR.iterdir())
    except OSError:
        return False


def ensure_running() -> bool:
    if not _flags_present():  # F1: stay up while ANY project reads
        return False
    if server_alive():
        return True
    try:
        RUN_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    except OSError:
        return False
    if not PIPER_DAEMON.exists():
        return False
    lock_fd = os.open(str(LOCK_FILE), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        if server_alive():
            return True
        pid = os.fork()
        if pid == 0:
            os.setsid()
            pid2 = os.fork()
            if pid2 == 0:
                try:
                    with open(os.devnull, "rb") as nin, open(os.devnull, "wb") as nout:
                        os.dup2(nin.fileno(), 0)
                        os.dup2(nout.fileno(), 1)
                        os.dup2(nout.fileno(), 2)
                except OSError:
                    pass
                try:
                    os.closerange(3, 1024)
                except OSError:
                    pass
                run_server()
                os._exit(0)
            os._exit(0)
        os.waitpid(pid, 0)
        for _ in range(50):
            if server_alive():
                return True
            time.sleep(0.1)
        return False
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        except OSError:
            pass


def _spawn_daemon() -> subprocess.Popen | None:
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{PIPER_LIB}:{env.get('LD_LIBRARY_PATH', '')}"
    env["ESPEAK_DATA_PATH"] = str(PIPER_ESPEAK)
    env["PIPER_VOICE_PATH"] = str(PIPER_VOICES)
    env["PIPER_LENGTH_SCALE"] = DEFAULT_LENGTH
    try:
        # F13: route the long-lived daemon's stderr to czytaj.log instead of
        # /dev/null so synth failures are diagnosable. The child keeps its own
        # dup of the fd, so closing our handle after spawn is fine.
        with open(cz.LOG_FILE, "a") as _errlog:
            d = subprocess.Popen(
                [str(PIPER_DAEMON), "-m", DEFAULT_VOICE],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=_errlog,
                env=env,
            )
    except (FileNotFoundError, OSError):
        return None
    ready = d.stdout.readline().decode("utf-8", errors="ignore").strip()
    if ready != "READY":
        try:
            d.kill()
        except OSError:
            pass
        return None
    return d


def synthesize_via_daemon(daemon: subprocess.Popen, text: str, raw_path: Path) -> bool:
    if daemon.poll() is not None:
        return False
    try:
        daemon.stdin.write(f"{raw_path}\n".encode("utf-8"))
        daemon.stdin.write(text.replace("\n", " ").encode("utf-8") + b"\n")
        daemon.stdin.flush()
    except (BrokenPipeError, OSError):
        return False
    fd = daemon.stdout.fileno()
    deadline = time.monotonic() + DAEMON_READ_TIMEOUT_S
    line_bytes = b""
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        ready, _, _ = select.select([fd], [], [], max(0.05, remaining))
        if not ready:
            continue
        chunk = os.read(fd, 64)
        if not chunk:
            break
        line_bytes += chunk
        if b"\n" in line_bytes:
            global _daemon_err_count
            line = line_bytes.split(b"\n", 1)[0].decode("utf-8", errors="ignore").strip()
            ok = line == "OK" and raw_path.exists()
            if ok:
                _daemon_err_count = 0
            else:
                # FD4: a persistent synth fault (ERR / missing out file) used to return False
                # WITHOUT recycling the daemon, so every later read failed silently. Recycle after
                # 2 consecutive failures (get_daemon respawns a clean one); a single transient ERR
                # keeps the warm daemon — no ~5s cold respawn for a one-off bad path.
                _daemon_err_count += 1
                if _daemon_err_count >= 2:
                    _daemon_err_count = 0
                    try:
                        daemon.kill()
                    except OSError:
                        pass
            return ok
    try:
        daemon.kill()
    except OSError:
        pass
    return False


def _wav_out_safe(wav_out: str) -> bool:
    try:
        p = Path(wav_out).resolve()
    except OSError:
        return False
    home = Path.home().resolve()
    tmp = Path(tempfile.gettempdir()).resolve()
    for base in (home, tmp, RUN_DIR.resolve()):
        try:
            p.relative_to(base)
            return True
        except ValueError:
            continue
    return False


def run_server() -> None:
    try:
        RUN_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    except OSError:
        return

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{PIPER_LIB}:{env.get('LD_LIBRARY_PATH', '')}"
    env["ESPEAK_DATA_PATH"] = str(PIPER_ESPEAK)
    env["PIPER_VOICE_PATH"] = str(PIPER_VOICES)
    env["PIPER_LENGTH_SCALE"] = DEFAULT_LENGTH

    daemon_holder = {"d": None}
    daemon = _spawn_daemon()
    daemon_holder["d"] = daemon

    sock = None
    daemon_lock = threading.Lock()
    shutdown_done = threading.Event()

    def get_daemon():
        d = daemon_holder["d"]
        if d is None or d.poll() is not None:
            d = _spawn_daemon()
            daemon_holder["d"] = d
        return d

    def shutdown(*_):
        if shutdown_done.is_set():
            return
        shutdown_done.set()
        with daemon_lock:
            d = daemon_holder.get("d")
            if d is not None:
                try:
                    if d.stdin:
                        d.stdin.close()
                except OSError:
                    pass
                try:
                    d.wait(timeout=2)
                except Exception:
                    try:
                        d.kill()
                    except OSError:
                        pass
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        for p in (SOCKET_PATH, PID_FILE):
            try:
                p.unlink()
            except OSError:
                pass
        sys.exit(0)

    try:
        if daemon is None:
            shutdown()
            return

        try:
            SOCKET_PATH.unlink()
        except FileNotFoundError:
            pass
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(SOCKET_PATH))
        try:
            os.chmod(str(SOCKET_PATH), 0o600)
        except OSError:
            pass
        sock.listen(4)
        sock.settimeout(SERVER_IDLE_TIMEOUT_S)

        PID_FILE.write_text(str(os.getpid()))

        signal.signal(signal.SIGTERM, shutdown)
        signal.signal(signal.SIGINT, shutdown)

        def handle(conn: socket.socket) -> None:
            try:
                data = b""
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if b"\n\n" in data:
                        break
                req_text = data.split(b"\n\n", 1)[0].decode("utf-8", errors="ignore")
                try:
                    req = json.loads(req_text)
                except json.JSONDecodeError:
                    conn.sendall(b'{"ok":false,"error":"bad-json"}\n')
                    return
                if req.get("ping"):   # S6: liveness probe — answer without synth
                    conn.sendall(b'{"ok":true}\n')
                    return
                text = req.get("text", "")
                wav_out = req.get("wav_out", "")
                if not text or not wav_out:
                    conn.sendall(b'{"ok":false,"error":"missing"}\n')
                    return
                if not _wav_out_safe(wav_out):
                    conn.sendall(b'{"ok":false,"error":"path"}\n')
                    return
                with daemon_lock:
                    d = get_daemon()
                    if d is None:
                        conn.sendall(b'{"ok":false,"error":"daemon-spawn"}\n')
                        return
                    ok = synthesize_via_daemon(d, text, Path(wav_out))
                if not ok:
                    conn.sendall(b'{"ok":false,"error":"synth"}\n')
                    return
                conn.sendall(
                    json.dumps(
                        {"ok": True, "raw": wav_out, "rate": DEFAULT_SAMPLE_RATE}
                    ).encode() + b"\n"
                )
            except Exception as e:
                try:
                    conn.sendall(json.dumps({"ok": False, "error": str(e)}).encode() + b"\n")
                except OSError:
                    pass
            finally:
                try:
                    conn.close()
                except OSError:
                    pass

        while not shutdown_done.is_set():
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                # Idle for SERVER_IDLE_TIMEOUT_S — but stay WARM while ANY project is
                # reading (a flag exists), so the next read-back/auto-read isn't a ~3-7s
                # cold start. Idle cost is ~0% CPU (sleeping). Only self-reap when reading
                # is fully off. Re-checked each timeout, so it reaps within one window
                # after the last /czytaj OFF.
                if _flags_present():   # RG2: exception-safe (no crash if FLAG_DIR vanishes mid-scan)
                    continue
                shutdown()
                return
            except OSError:
                if shutdown_done.is_set():
                    return
                raise
            threading.Thread(target=handle, args=(conn,), daemon=True).start()
    finally:
        shutdown()


def speak_raw(text: str, raw_out: Path, timeout_s: float = 45.0) -> int | None:  # 2026-06-15: was 12; must exceed DAEMON_READ_TIMEOUT_S so the server kills+responds first
    """Synthesize text into raw float32 PCM at raw_out via the daemon.
    Returns the sample rate on success, None on failure."""
    if not ensure_running():
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout_s)
    try:
        try:
            s.connect(str(SOCKET_PATH))
        except OSError:
            return None
        try:
            req = json.dumps({"text": text, "wav_out": str(raw_out)}).encode("utf-8")
            s.sendall(req + b"\n\n")
            data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
                if b"\n" in data:
                    break
            try:
                resp = json.loads(data.decode("utf-8", errors="ignore").strip())
            except json.JSONDecodeError:
                return None
            if not resp.get("ok"):
                return None
            return int(resp.get("rate") or DEFAULT_SAMPLE_RATE)
        except OSError:
            return None
    finally:
        try:
            s.close()
        except OSError:
            pass


def speak(text: str, wav_out: Path, timeout_s: float = 45.0) -> bool:  # 2026-06-15: was 12
    return speak_raw(text, wav_out, timeout_s) is not None


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "start":
        # F20: race-safe spawn (toggle.sh uses this). ensure_running holds
        # LOCK_FILE + re-checks server_alive, so it can't double-bind/orphan a
        # daemon a client's ensure_running already started (the old `serve` path
        # bound unconditionally and stole the socket).
        ensure_running()
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        # SD2: the old bare run_server() bound the socket with NO lock, so a stray
        # `serve` could double-bind and steal the socket from the warm daemon. Route
        # it through the same flock-guarded spawn as `start` (nothing calls `serve`
        # today — toggle.sh uses `start` — so this only hardens a latent entrypoint;
        # run_server() stays the in-fork server body invoked under ensure_running's lock).
        ensure_running()
        sys.exit(0)
    if len(sys.argv) < 2:
        print("usage: piper_server.py start | serve | <text>", file=sys.stderr)
        sys.exit(1)
    text = sys.argv[1]
    out = Path(tempfile.mkstemp(suffix=".wav")[1])
    if speak(text, out):
        print(out)
        sys.exit(0)
    sys.exit(1)
