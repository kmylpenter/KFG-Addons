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

PIPER_HOME = Path(os.environ.get("PIPER_HOME", str(Path.home() / "piper-tts")))
PIPER_DAEMON = PIPER_HOME / "piper1-gpl" / "libpiper" / "piper-daemon"
PIPER_LIB = PIPER_HOME / "piper1-gpl" / "libpiper" / "install" / "lib"
PIPER_ESPEAK = PIPER_HOME / "piper1-gpl" / "libpiper" / "install" / "espeak-ng-data"
PIPER_VOICES = PIPER_HOME / "voices"
FLAG_FILE = Path.home() / ".claude" / "czytaj.flag"

RUN_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", os.environ.get("TMPDIR", "/tmp"))) / "piper-server"
SOCKET_PATH = RUN_DIR / "server.sock"
PID_FILE = RUN_DIR / "server.pid"
LOCK_FILE = RUN_DIR / "server.lock"
DEFAULT_VOICE = os.environ.get("PIPER_VOICE", "pl_PL-gosia-medium")
DEFAULT_LENGTH = os.environ.get("PIPER_LENGTH_SCALE", "0.6")
try:
    DEFAULT_SAMPLE_RATE = int(os.environ.get("PIPER_SAMPLE_RATE", "22050"))
except ValueError:
    DEFAULT_SAMPLE_RATE = 22050
SERVER_IDLE_TIMEOUT_S = int(os.environ.get("PIPER_IDLE_TIMEOUT", "1800"))
DAEMON_READ_TIMEOUT_S = float(os.environ.get("PIPER_DAEMON_TIMEOUT", "30"))


def _is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _can_connect(timeout: float = 0.2) -> bool:
    if not SOCKET_PATH.exists():
        return False
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(SOCKET_PATH))
        return True
    except OSError:
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
    if not _can_connect():
        return False
    return True


def ensure_running() -> bool:
    if not FLAG_FILE.is_file():
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
        d = subprocess.Popen(
            [str(PIPER_DAEMON), "-m", DEFAULT_VOICE],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
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
            line = line_bytes.split(b"\n", 1)[0].decode("utf-8", errors="ignore").strip()
            return line == "OK" and raw_path.exists()
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
                shutdown()
                return
            except OSError:
                if shutdown_done.is_set():
                    return
                raise
            threading.Thread(target=handle, args=(conn,), daemon=True).start()
    finally:
        shutdown()


def speak_raw(text: str, raw_out: Path, timeout_s: float = 30.0) -> int | None:
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


def speak(text: str, wav_out: Path, timeout_s: float = 30.0) -> bool:
    return speak_raw(text, wav_out, timeout_s) is not None


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        run_server()
        sys.exit(0)
    if len(sys.argv) < 2:
        print("usage: piper_server.py serve | <text>", file=sys.stderr)
        sys.exit(1)
    text = sys.argv[1]
    out = Path(tempfile.mkstemp(suffix=".wav")[1])
    if speak(text, out):
        print(out)
        sys.exit(0)
    sys.exit(1)
