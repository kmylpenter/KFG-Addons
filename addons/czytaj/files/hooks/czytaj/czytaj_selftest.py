#!/usr/bin/env python3
"""czytaj canary / self-test — empirical verification net for the SSOT refactor (2026-06-15).

czytaj has no unit tests; this is the net. It runs against ITS OWN directory, so
`python3 czytaj_selftest.py` checks the repo copy and, after install,
`python3 ~/.claude/hooks/czytaj/czytaj_selftest.py` checks the LIVE runtime.

Checks:
  1. every czytaj python module imports cleanly
  2. czytaj_paths values are well-formed
  3. SHELL<->PYTHON parity (the S2/S3 drift guard): czytaj-env.sh czytaj_project_key equals
     czytaj_paths.project_key, and CZYTAJ_RUN_DIR/CZYTAJ_FLAG_DIR equal the python values
  4. the gate hooks (stop.py, pre-tool-use.py) run with a fake OFF stdin and exit 0 cleanly
  5. bash -n on every shell script

Exit 0 = all green; non-zero = a check failed (printed). This is intentionally a RUNTIME
canary (catches the str/Path + cross-language key drift that has no compile-time signal).
"""
import hashlib
import json
import os
import subprocess
import sys

HOOK_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HOOK_DIR)
FAILS = []


def check(name, ok, detail=""):
    print(f"  [{'OK' if ok else 'XX'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        FAILS.append(name)


# 1. imports -----------------------------------------------------------------
try:
    import czytaj_paths as cz
    import _speak  # noqa: F401
    import piper_server  # noqa: F401
    import piper_stream  # noqa: F401
    import volume_watcher  # noqa: F401
    check("python modules import", True, "czytaj_paths/_speak/piper_server/piper_stream/volume_watcher")
except Exception as e:  # pragma: no cover
    check("python modules import", False, repr(e))
    print("\nSELFTEST FAILED: imports broken — aborting")
    sys.exit(1)

# 2. czytaj_paths well-formed ------------------------------------------------
home = os.path.expanduser("~")
check("czytaj_paths values well-formed",
      bool(cz.FLAG_DIR.startswith(home) and cz.RUN_DIR and cz.LOG_FILE.startswith(home)
           and cz.PIPER_VOICE and cz.PIPER_SAMPLE_RATE > 0 and cz.PIPER_LENGTH_SCALE),
      f"FLAG_DIR={cz.FLAG_DIR} RUN_DIR={cz.RUN_DIR} voice={cz.PIPER_VOICE} rate={cz.PIPER_SAMPLE_RATE}")

# 3. shell<->python parity (the SSOT drift guard) ----------------------------
env_sh = os.path.join(HOOK_DIR, "czytaj-env.sh")
if os.path.isfile(env_sh):
    for d in ("/root/projekty/KFG-Addons", home, "/tmp"):
        if not os.path.isdir(d):
            continue
        try:
            shell = subprocess.run(
                ["bash", "-c", f'source "{env_sh}"; czytaj_project_key "$1"', "_", d],
                capture_output=True, text=True, timeout=10).stdout.strip()
        except Exception as e:
            shell = f"<err {e}>"
        # czytaj-env.sh hashes realpath of the LITERAL dir; match that exactly.
        py = hashlib.sha1(os.path.realpath(d).encode("utf-8")).hexdigest()
        check(f"shell==python key [{d}]", shell == py, f"shell={shell} py={py}")
    rd = subprocess.run(["bash", "-c", f'source "{env_sh}"; printf %s "$CZYTAJ_RUN_DIR"'],
                        capture_output=True, text=True).stdout.strip()
    fd = subprocess.run(["bash", "-c", f'source "{env_sh}"; printf %s "$CZYTAJ_FLAG_DIR"'],
                        capture_output=True, text=True).stdout.strip()
    check("shell==python RUN_DIR", rd == cz.RUN_DIR, f"shell={rd} py={cz.RUN_DIR}")
    check("shell==python FLAG_DIR", fd == cz.FLAG_DIR, f"shell={fd} py={cz.FLAG_DIR}")
else:
    check("czytaj-env.sh present", False, env_sh)

# 4. gate hooks run with an OFF stdin and exit 0 -----------------------------
fake = json.dumps({"cwd": "/tmp/__czytaj_selftest_no_such_project__", "transcript_path": ""})
for hook in ("stop.py", "pre-tool-use.py"):
    p = os.path.join(HOOK_DIR, hook)
    if os.path.isfile(p):
        r = subprocess.run([sys.executable or "python3", p], input=fake,
                           capture_output=True, text=True, timeout=30)
        check(f"{hook} OFF-stdin exit 0", r.returncode == 0,
              f"rc={r.returncode} err={r.stderr.strip()[:120]}")

# 5. bash -n on every shell script -------------------------------------------
for sh in ("czytaj-env.sh", "toggle.sh", "user-prompt-submit.sh", "stop.sh", "pre-tool-use.sh"):
    p = os.path.join(HOOK_DIR, sh)
    if os.path.isfile(p):
        r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
        check(f"bash -n {sh}", r.returncode == 0, r.stderr.strip()[:120])

print()
if FAILS:
    print(f"SELFTEST FAILED: {len(FAILS)} check(s) — {', '.join(FAILS)}")
    sys.exit(1)
print("SELFTEST PASSED — all green")
sys.exit(0)
