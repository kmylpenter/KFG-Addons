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
    sk = subprocess.run(["bash", "-c", f'source "{env_sh}"; printf %s "$CZYTAJ_SHIZUKU_FLAG"'],
                        capture_output=True, text=True).stdout.strip()
    check("shell==python SHIZUKU_FLAG", sk == cz.SHIZUKU_FLAG, f"shell={sk} py={cz.SHIZUKU_FLAG}")
    # M7: pin the other cross-language SSOT values too (written by bash AND read/written by
    # python, consumed cross-process) so a one-sided rename of any of them drifts RED here.
    for var, pyval, label in (("CZYTAJ_LOG", cz.LOG_FILE, "LOG_FILE"),
                              ("CZYTAJ_PAUSE_FLAG", cz.PAUSE_FLAG, "PAUSE_FLAG"),
                              ("CZYTAJ_KEYPAUSE_STATE", cz.KEYPAUSE_STATE, "KEYPAUSE_STATE")):
        sv = subprocess.run(["bash", "-c", f'source "{env_sh}"; printf %s "${var}"'],
                            capture_output=True, text=True).stdout.strip()
        check(f"shell==python {label}", sv == pyval, f"shell={sv} py={pyval}")
    # M13: pin the in-turn audio-client kill set (shell array == python tuple), so adding/removing
    # an audio client can't silently diverge the two languages (the shotgun-surgery the audit flagged).
    acp = subprocess.run(
        ["bash", "-c", f'source "{env_sh}"; printf "%s\\n" "${{CZYTAJ_AUDIO_CLIENT_PATS[@]}}"'],
        capture_output=True, text=True).stdout.strip().splitlines()
    check("shell==python AUDIO_CLIENT_PATS", acp == list(cz.AUDIO_CLIENT_PATS),
          f"shell={acp} py={list(cz.AUDIO_CLIENT_PATS)}")
    # ENV-RESOLUTION parity (S3's ACTUAL divergence vector, not just the sha1 algorithm):
    # exercise the full caller path — shell ${CLAUDE_PROJECT_DIR:-$PWD}+czytaj_project_key vs
    # python project_key() (project_dir() = CLAUDE_PROJECT_DIR or cwd or getcwd()) — under
    # unset / empty-string / set, so a future regression in EITHER resolution goes RED here.
    tcwd = "/root/projekty/KFG-Addons" if os.path.isdir("/root/projekty/KFG-Addons") else home
    tother = "/root" if tcwd != "/root" else "/tmp"   # a dir != cwd, so 'set' truly exercises resolution
    base = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    base["PWD"] = tcwd
    base["PYTHONPATH"] = HOOK_DIR + os.pathsep + base.get("PYTHONPATH", "")  # import czytaj_paths from a foreign cwd
    for label, cpd in (("unset", None), ("empty", ""), ("set-distinct", tother)):
        e = dict(base) if cpd is None else {**base, "CLAUDE_PROJECT_DIR": cpd}
        shk = subprocess.run(
            ["bash", "-c", f'source "{env_sh}"; czytaj_project_key "${{CLAUDE_PROJECT_DIR:-$PWD}}"'],
            capture_output=True, text=True, env=e, cwd=tcwd).stdout.strip()
        pyk = subprocess.run(
            [sys.executable or "python3", "-c", "import czytaj_paths as c; print(c.project_key(''))"],
            capture_output=True, text=True, env=e, cwd=tcwd).stdout.strip()
        check(f"env-resolution key parity [CLAUDE_PROJECT_DIR {label}]",
              shk == pyk and len(shk) == 40, f"shell={shk} py={pyk}")
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

# 6. volume-key gate (2026-10-05) ---------------------------------------------
# Regression: with Shizuku gone, rish times out (~7s) → the foreground probe failed CLOSED and
# EVERY accessibility key press was dropped as "locked/other-app". A DEAD probe must now trust the
# a11y flag (the service gates Termux-foreground + unlocked itself); a WORKING probe still gates.
vw = volume_watcher
import tempfile
_orig = (vw._run_shell, vw._czytaj_audio_playing, vw._read_back, vw._toggle_pause, vw.FLAG_DIR)
vw.FLAG_DIR = tempfile.mkdtemp(prefix="czytaj-selftest-flags-")
open(os.path.join(vw.FLAG_DIR, ".keepwarm-readback"), "w").close()   # dotfile ≠ reading on
fired = []
vw._czytaj_audio_playing = lambda: False
vw._read_back = lambda: fired.append("up")
vw._toggle_pause = lambda: fired.append("down")
try:
    # 2026-10-10 (Kamil): read-back ON DEMAND works with /czytaj OFF everywhere too — /czytaj only
    # switches AUTO-reading; a volume key in Termux always reads (supersedes the 2026-10-06 OFF gate).
    fired.clear()
    vw._fg_cache.update({"t": 0.0, "v": False, "dead_t": None})
    vw._run_shell = lambda *a, **k: (False, "")
    vw._gated_action(vw.KEY_VOLUMEUP)
    check("volume gate: /czytaj OFF everywhere → still reads on demand", fired == ["up"], f"fired={fired}")
    open(os.path.join(vw.FLAG_DIR, "selftestproject.flag"), "w").close()   # /czytaj ON in one project
    for label, probe, want in (
        ("dead probe (Shizuku gone) → act", (False, ""), ["up"]),
        ("probe says other app → skip", (True, "mCurrentFocus=Window{1 u0 com.android.systemui}"), []),
        ("probe says Termux → act", (True, "mCurrentFocus=Window{1 u0 com.termux/.app.TermuxActivity}"), ["up"]),
    ):
        fired.clear()
        vw._fg_cache.update({"t": 0.0, "v": False, "dead_t": None})
        vw._run_shell = lambda *a, _p=probe, **k: _p
        vw._gated_action(vw.KEY_VOLUMEUP)
        check(f"volume gate: {label}", fired == want, f"fired={fired}")
finally:
    import shutil
    shutil.rmtree(vw.FLAG_DIR, ignore_errors=True)   # our own mkdtemp dir
    vw._run_shell, vw._czytaj_audio_playing, vw._read_back, vw._toggle_pause, vw.FLAG_DIR = _orig

# 7. /czytaj toggles WITHOUT a model turn (2026-10-06) ------------------------
# The UserPromptSubmit hook intercepts the /czytaj prompt, runs toggle.sh and BLOCKS the prompt
# (decision:block) so Claude never answers. A message merely mentioning /czytaj must pass through.
import tempfile as _tf


def _sandbox_home(prefix):
    """Isolated HOME (hooks symlinked) + PATH shims, so the toggle/UPS hooks under test touch
    NOTHING live (2026-10-10: the selftest's global `pkill` of piper_stream/paplay/media-player
    cut the user's read-back mid-play, and a real-HOME ON/OFF reset the active-session marker)."""
    h = _tf.mkdtemp(prefix=prefix)
    os.makedirs(os.path.join(h, ".claude", "czytaj-flags"))
    os.symlink(os.path.dirname(HOOK_DIR), os.path.join(h, ".claude", "hooks"))
    b = os.path.join(h, "bin")
    os.makedirs(b)
    for name, body in (("pkill", 'echo "$*" >> "$HOME/pkill.log"; exit 1'), ("nohup", "exit 0"),
                       ("termux-media-player", "exit 0")):
        with open(os.path.join(b, name), "w") as f:
            f.write(f"#!/bin/sh\n{body}\n")
        os.chmod(os.path.join(b, name), 0o755)
    return h, b


_proj = _tf.mkdtemp(prefix="czytaj-selftest-proj-")
_home7, _bin7 = _sandbox_home("czytaj-selftest-home7-")
# key from the temp dir itself (NOT cz.project_key(): that prefers $CLAUDE_PROJECT_DIR, i.e. the
# REAL session project — the first draft of this test toggled the user's own flag).
_flag = os.path.join(_home7, ".claude", "czytaj-flags",
                     hashlib.sha1(os.path.realpath(_proj).encode()).hexdigest() + ".flag")
_ups = os.path.join(HOOK_DIR, "user-prompt-submit.sh")


def _ups_run(prompt):
    env = {**os.environ, "CLAUDE_PROJECT_DIR": _proj, "HOME": _home7,
           "PATH": _bin7 + os.pathsep + os.environ["PATH"]}
    return subprocess.run(["bash", _ups], input=json.dumps({"prompt": prompt, "transcript_path": ""}),
                          capture_output=True, text=True, timeout=30, env=env, cwd=_proj).stdout


try:
    out = _ups_run("/czytaj")
    check("/czytaj ON: blocked + flag set", '"decision": "block"' in out.replace('":"', '": "')
          and os.path.isfile(_flag), out.strip()[:120])
    try:   # reading ON + an ordinary prompt → the context JSON Claude Code must be able to parse
        _ctx = json.loads(_ups_run("zwykla wiadomosc"))["hookSpecificOutput"]["additionalContext"]
    except (ValueError, KeyError) as e:
        _ctx = f"<invalid: {e!r}>"
    check("UPS context JSON valid when reading ON", _ctx.startswith("TRYB CZYTANIA"), _ctx[:80])
    # 2026-10-10: ONE pkill per audio-client sweep — each pkill scans /proc (~1.1s on PRoot), and
    # the old per-pattern loop cost ~4.5s on every prompt while reading ON (and ~10s for /czytaj OFF).
    _pk = os.path.join(_home7, "pkill.log")
    _calls7 = open(_pk).read().splitlines() if os.path.isfile(_pk) else []
    check("UPS (reading ON): one pkill sweeps every audio client",
          len(_calls7) == 1 and all(pt in _calls7[0] for pt in cz.AUDIO_CLIENT_PATS), str(_calls7))
    out = _ups_run("<command-message>czytaj</command-message>\n<command-name>/czytaj</command-name>")
    check("/czytaj OFF (expanded form): blocked + flag cleared", '"decision": "block"' in out.replace('":"', '": "')
          and not os.path.isfile(_flag), out.strip()[:120])
    out = _ups_run("czy /czytaj da sie zrobic bez modelu?")
    check("prose mentioning /czytaj passes through", "block" not in out and not os.path.isfile(_flag),
          out.strip()[:120])
finally:
    if os.path.isfile(_flag):
        os.remove(_flag)   # our own temp project's flag
    os.rmdir(_proj)
    import shutil as _sh7
    _sh7.rmtree(_home7, ignore_errors=True)   # our own mkdtemp sandbox

# 8. /czytaj OFF of the LAST reading project stays under the hook timeout (2026-10-06) ----------
# Live bug: toggle.sh's teardown ran `termux-media-player stop` in the FOREGROUND; Termux:API took
# >10s, Claude Code killed the hook, the block never arrived and the prompt reached the model.
# Isolated HOME (hooks symlinked) so FLAG_DIR holds ONLY our flag → the teardown path runs;
# a PATH shim makes termux-media-player hang like the real one.
import time as _t
_home, _bin = _sandbox_home("czytaj-selftest-home-")   # + pkill/nohup shims: no live process is hit
with open(os.path.join(_bin, "termux-media-player"), "w") as f:   # overrides the no-op shim: hangs
    f.write("#!/bin/sh\nsleep 20\n")
os.chmod(os.path.join(_bin, "termux-media-player"), 0o755)
_p2 = _tf.mkdtemp(prefix="czytaj-selftest-proj2-")
open(os.path.join(_home, ".claude", "czytaj-flags",
                  hashlib.sha1(os.path.realpath(_p2).encode()).hexdigest() + ".flag"), "w").close()
_env = {**os.environ, "HOME": _home, "CLAUDE_PROJECT_DIR": _p2, "PATH": _bin + os.pathsep + os.environ["PATH"]}
_t0 = _t.monotonic()
try:
    _out = subprocess.run(["bash", _ups], input=json.dumps({"prompt": "/czytaj", "transcript_path": ""}),
                          capture_output=True, text=True, timeout=30, env=_env, cwd=_p2).stdout
except subprocess.TimeoutExpired:
    _out = ""
_dt = _t.monotonic() - _t0
check("/czytaj OFF (last project) answers < 8s with a block", _dt < 8 and '"decision":"block"' in _out,
      f"{_dt:.1f}s out={_out.strip()[:80]}")
_pk8 = os.path.join(_home, "pkill.log")
_calls8 = open(_pk8).read().splitlines() if os.path.isfile(_pk8) else []
check("/czytaj OFF teardown: one pkill sweeps every audio client",
      len(_calls8) == 1 and all(pt in _calls8[0] for pt in cz.AUDIO_CLIENT_PATS), str(_calls8))
_sp_run = _speak.subprocess.run
_calls_py = []
_speak.subprocess.run = lambda argv, *a, **k: (_calls_py.append(argv)
                                               or subprocess.CompletedProcess(argv, 1, stdout="", stderr=""))
try:
    _speak._kill_audio_chain()   # runs before EVERY Vol+ read-back
finally:
    _speak.subprocess.run = _sp_run
_pk_py = [c for c in _calls_py if c and c[0] == "pkill"]
check("Vol+ audio stop: one pkill sweeps every audio client",
      len(_pk_py) == 1 and all(pt in _pk_py[0][-1] for pt in cz.AUDIO_CLIENT_PATS), str(_pk_py))
subprocess.run(["pkill", "-f", _bin], capture_output=True)   # reap our own sleeping shim
import shutil as _sh
_sh.rmtree(_home, ignore_errors=True)
os.rmdir(_p2)

# 9. In-app playback bridge: watcher's /press decision (2026-10-06) ---------------------------
# The Voice Keyboard asks the watcher (127.0.0.1) what to play and plays the cached wav ITSELF —
# skipping the ~2.4s-per-call termux-media-player bridge. _press(key, fg, app_playing) → (status, body).
_o9 = (vw.FLAG_DIR, vw.readback_cached_wav, vw.read_message_back, vw._toggle_pause,
       vw._czytaj_audio_playing, vw._stop_termux_audio)
_fd9 = _tf.mkdtemp(prefix="czytaj-selftest-flags9-")
_wav9 = os.path.join(_fd9, "x.wav")
with open(_wav9, "wb") as f:
    f.write(b"RIFF-test-wav")
_calls9 = []
vw.FLAG_DIR = _fd9
vw.readback_cached_wav = lambda n: (_calls9.append(("wav", n)) or _wav9)
vw.read_message_back = lambda n: _calls9.append(("synth", n))
vw._toggle_pause = lambda: _calls9.append(("pause",))
vw._czytaj_audio_playing = lambda: False
vw._stop_termux_audio = lambda: _calls9.append(("stop-termux",))
try:
    vw._last_read_ts = -1e9
    st, body = vw._press("up", "termux", False)
    check("bridge: /czytaj OFF → Vol+ in Termux still 200 + wav", st == 200 and body == b"RIFF-test-wav",
          f"{st} {_calls9}")
    _calls9.clear()
    vw._last_read_ts = -1e9
    open(os.path.join(_fd9, "proj.flag"), "w").close()
    st, body = vw._press("up", "termux", False)
    check("bridge: Vol+ in Termux → 200 + wav of n=1", st == 200 and body == b"RIFF-test-wav"
          and ("wav", 1) in _calls9 and ("stop-termux",) in _calls9, f"{st} {_calls9}")
    _calls9.clear()
    st, body = vw._press("up", "termux", True)
    check("bridge: Vol+ while app plays → scrub n=2", st == 200 and ("wav", 2) in _calls9, f"{st} {_calls9}")
    _calls9.clear()
    vw.readback_cached_wav = lambda n: (_calls9.append(("wav", n)) or "")
    vw._last_read_ts = -1e9
    st, body = vw._press("up", "termux", False)
    for _ in range(40):   # the MISS synth is started on a THREAD — wait for it, or it lands in the next check
        if ("synth", 1) in _calls9:
            break
        _t.sleep(0.05)
    check("bridge: cache MISS → 202 + Termux-side synth", st == 202 and ("synth", 1) in _calls9, f"{st} {_calls9}")
    _calls9.clear()
    st, body = vw._press("up", "locked", False)
    check("bridge: locked + nothing playing → 204", st == 204 and not _calls9, f"{st} {_calls9}")
    vw._czytaj_audio_playing = lambda: True
    st, body = vw._press("down", "locked", False)
    check("bridge: Vol- locked while Termux reads → pause", st == 204 and ("pause",) in _calls9, f"{st} {_calls9}")
finally:
    (vw.FLAG_DIR, vw.readback_cached_wav, vw.read_message_back, vw._toggle_pause,
     vw._czytaj_audio_playing, vw._stop_termux_audio) = _o9
    _sh.rmtree(_fd9, ignore_errors=True)

# 10. Reading settings from the keyboard's "Czytanie" tab (2026-10-06) ----------------------------
# voice / speed / keys on-off / swap / scrub window live in czytaj-settings.json; the keyboard
# reads+writes them through the bridge (/status, /set, /toggle).
_sf = os.path.join(_tf.mkdtemp(prefix="czytaj-selftest-settings-"), "s.json")
d = cz.load_settings(_sf)
check("settings: defaults = today's behaviour", d["voice"] == "pl_PL-gosia-medium"
      and abs(float(cz.length_scale_for(d["speed"])) - 0.6) < 1e-6 and d["keys"] and not d["swap"], str(d))
d = cz.save_settings({"voice": "pl_PL-darkman-medium", "speed": 2.0, "swap": True}, _sf)
check("settings: save merges + persists", cz.load_settings(_sf) == d and d["voice"] == "pl_PL-darkman-medium"
      and d["keys"] and cz.length_scale_for(d["speed"]) == "0.500", str(d))
d = cz.save_settings({"voice": "../../etc/passwd", "speed": 99, "scrub_s": -3}, _sf)
check("settings: bad values rejected/clamped", d["voice"] == "pl_PL-darkman-medium" and d["speed"] <= 3.0
      and d["scrub_s"] >= 1, str(d))
_o10 = (vw.load_settings, vw.FLAG_DIR)
_fd10 = _tf.mkdtemp(prefix="czytaj-selftest-flags10-")
open(os.path.join(_fd10, "p.flag"), "w").close()
vw.FLAG_DIR = _fd10
try:
    vw.load_settings = lambda: {**cz.SETTINGS_DEFAULTS, "keys": False}
    st, _ = vw._press("up", "termux", False)
    check("settings: keys OFF → bridge 204", st == 204, str(st))
finally:
    vw.load_settings, vw.FLAG_DIR = _o10
    _sh.rmtree(_fd10, ignore_errors=True)
_sp = _speak.__dict__
k1 = _speak._readback_key("tekst", {**cz.SETTINGS_DEFAULTS})
k2 = _speak._readback_key("tekst", {**cz.SETTINGS_DEFAULTS, "voice": "pl_PL-darkman-medium"})
check("settings: read-back cache keyed by voice", k1 != k2, f"{k1[:8]} {k2[:8]}")
_sh.rmtree(os.path.dirname(_sf), ignore_errors=True)

# 11. /czytaj ON = AUTO-read in that window; OFF = silent until a volume key (Kamil 2026-10-10) ----
# Supersedes 2026-10-07 "on demand only". The Stop + PreToolUse hooks speak by themselves only where
# /czytaj is ON (is_active(cwd)); the Stop hook pre-renders for Vol+ regardless of mode.
import importlib.util as _iu
import io as _io


def _load_hook(name):
    spec = _iu.spec_from_file_location(name.replace("-", "_"), os.path.join(HOOK_DIR, name))
    m = _iu.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _run_hooks(active):
    said, pre = [], []
    for hook in ("stop.py", "pre-tool-use.py"):
        m = _load_hook(hook)
        m.is_active = lambda *a, **k: active
        m.is_recording = lambda: False
        m.is_in_call = lambda: False
        m.speak_new_text = lambda *a, _h=hook, **k: said.append(_h) or 0
        if hasattr(m, "_precache_latest"):
            m._precache_latest = lambda t: pre.append(t)
        _stdin = sys.stdin
        sys.stdin = _io.StringIO(json.dumps({"cwd": "/root/projekty/X", "transcript_path": "/tmp/t.jsonl"}))
        try:
            m.main()
        finally:
            sys.stdin = _stdin
    return said, pre


_said, _pre = _run_hooks(True)
check("auto-read: reading ON → Stop + PreToolUse speak", sorted(_said) == ["pre-tool-use.py", "stop.py"],
      f"spoke from {_said}")
check("auto-read: Stop hook pre-renders for Vol+ (reading ON)", _pre == ["/tmp/t.jsonl"], str(_pre))
_said, _pre = _run_hooks(False)
check("auto-read: reading OFF → no hook speaks by itself", _said == [], f"spoke from {_said}")
check("auto-read: Stop hook pre-renders for Vol+ (reading OFF)", _pre == ["/tmp/t.jsonl"], str(_pre))

# 12. Vol+ reads the tmux window ON SCREEN, not another session's (Kamil 2026-10-10) -------------
# Regression: a DETACHED background session (auto-wznow) has its own active window, so the
# "11" (pane_active+window_active) match hit it first → Termux home → wrong window read back.
# Also: a stale tmux-0 socket (plain `tmux` run from PRoot, no server) was picked as the newest
# socket → empty answer → fallback to an old session marker → another window read back.
import re as _re

_panes12 = [  # as list-panes -a prints them: sessions alphabetical, auto-wznow before main
    {"session_name": "auto-wznow", "session_attached": "0", "session_activity": "1790912580",
     "pane_active": "1", "window_active": "1", "pane_current_path": _speak.TERMUX_HOME},
    {"session_name": "main", "session_attached": "1", "session_activity": "1791620491",
     "pane_active": "1", "window_active": "0", "pane_current_path": _speak.TERMUX_HOME + "/projekty/UtilityHub"},
    {"session_name": "main", "session_attached": "1", "session_activity": "1791620491",
     "pane_active": "1", "window_active": "1", "pane_current_path": _speak.TERMUX_HOME + "/projekty/StairsForYou"},
]


def _fake_tmux12(argv, **k):
    if "/tmux-0/" in argv[argv.index("-S") + 1]:   # stale PRoot-uid socket: no server behind it
        return subprocess.CompletedProcess(argv, 1, stdout="", stderr="no server running")
    fmt = argv[argv.index("-F") + 1]
    out = "\n".join(_re.sub(r"#\{(\w+)\}", lambda m, _p=p: _p.get(m.group(1), ""), fmt) for p in _panes12)
    return subprocess.CompletedProcess(argv, 0, stdout=out + "\n", stderr="")


_o12 = (_speak.subprocess.run, _speak._transcript_for_project)
_speak.subprocess.run = _fake_tmux12
_speak._transcript_for_project = lambda p: p
_real_isfile = os.path.isfile
_speak.os.path.isfile = lambda p: p.endswith("/bin/tmux") or _real_isfile(p)
import glob as _glob12
_real_glob = _glob12.glob
_glob12.glob = lambda pat, *a, **k: ["/fake/tmux-0/default", "/fake/tmux-10387/default"] if "tmux-" in pat else _real_glob(pat, *a, **k)
try:
    _got12 = _speak._tmux_active_transcript_raw()
finally:
    _speak.subprocess.run, _speak._transcript_for_project = _o12[0], _o12[1]
    _speak.os.path.isfile = _real_isfile
    _glob12.glob = _real_glob
check("Vol+ window: live tmux socket + on-screen session win (dead socket, detached session)",
      _got12 == "/root/projekty/StairsForYou", f"got={_got12!r}")

# 13. A superseded synth server exits at once, not after 30 min idle (2026-10-10) ---------------
# Live: 5 server generations piled up (one per missed ping), each pinning a ~86MB piper-daemon and
# CPU, and the cold one-shot fallback timed out at 60s. A new generation must retire the old one.
# Real daemon, isolated short HOME (AF_UNIX path limit is 108 chars).
import signal as _sig
_h13 = _tf.mkdtemp(prefix="czh13-", dir="/tmp")
os.makedirs(os.path.join(_h13, ".claude", "czytaj-flags"))
open(os.path.join(_h13, ".claude", "czytaj-flags", "x.flag"), "w").close()
_env13 = {**os.environ, "HOME": _h13}
_pidf13 = os.path.join(_h13, ".cache", "czytaj", "piper-server", "server.pid")
_srv = os.path.join(HOOK_DIR, "piper_server.py")


def _pid13():
    try:
        return int(open(_pidf13).read().strip())
    except (OSError, ValueError):
        return 0


def _alive13(p):
    try:
        os.kill(p, 0)
        return True
    except OSError:
        return False


_a13 = _b13 = 0
try:
    # Generation A spawned by a CLIENT (as precache/piper_stream do). It must run as its own
    # piper_server.py process: a fork() inherited the client's argv, so the audio-client
    # `pkill -f 'python.*piper_stream\.py'` (UPS hook every turn, /czytaj OFF) killed the server too.
    subprocess.run([sys.executable or "python3", "-c",
                    "import sys; sys.path.insert(0, %r); import piper_server; piper_server.ensure_running()" % HOOK_DIR],
                   env=_env13, timeout=60)
    _a13 = _pid13()
    try:
        _cmd13 = open(f"/proc/{_a13}/cmdline", "rb").read().replace(b"\0", b" ").decode()
    except OSError:
        _cmd13 = ""
    check("synth server: runs as piper_server.py, not under the spawning client's argv",
          "piper_server.py" in _cmd13 and "-c" not in _cmd13.split(), f"pid={_a13} cmd={_cmd13[:90]!r}")
    os.unlink(os.path.join(_h13, ".cache", "czytaj", "piper-server", "server.sock"))   # = a missed ping
    subprocess.run([sys.executable or "python3", _srv, "start"], env=_env13, timeout=60)
    _b13 = _pid13()
    _t13 = _t.monotonic()
    while _a13 and _alive13(_a13) and _t.monotonic() - _t13 < 8:
        _t.sleep(0.2)
    check("synth server: a superseded generation exits (no orphan daemon)",
          _a13 > 0 and _b13 > 0 and _a13 != _b13 and not _alive13(_a13),
          f"old={_a13} alive={_alive13(_a13) if _a13 else '-'} new={_b13}")
finally:
    for _p in (_a13, _b13):
        if _p and _alive13(_p):
            os.kill(_p, _sig.SIGTERM)
    _t.sleep(2.5)   # let shutdown() stop each piper-daemon before the dir goes
    _sh.rmtree(_h13, ignore_errors=True)

# 14. A slow-to-answer server is waited for, not cut off (2026-10-10) ---------------------------
# Live: a fresh generation is bound + PID-written but on PRoot needs a moment to reach accept();
# the waiting client's 0.3s ping missed it and server_alive() UNLINKED the live server's socket —
# unreachable for good, the next client spawned another generation (588 "no pong" in one morning).
_h14 = _tf.mkdtemp(prefix="czh14-", dir="/tmp")
os.makedirs(os.path.join(_h14, ".claude", "czytaj-flags"))
_r14 = subprocess.run([sys.executable or "python3", "-c", r'''
import json, os, socket, sys, threading, time
sys.path.insert(0, %r)
import piper_server as ps
ps.RUN_DIR.mkdir(parents=True, exist_ok=True)
s = socket.socket(socket.AF_UNIX); s.bind(str(ps.SOCKET_PATH)); s.listen(4)
ps.PID_FILE.write_text(str(os.getpid()))
def late_accept():
    time.sleep(0.8)                       # bound + PID written, accept() not reached yet
    while True:
        c, _ = s.accept(); c.recv(256); c.sendall(b'{"ok":true}\n'); c.close()
threading.Thread(target=late_accept, daemon=True).start()
ok = False
t0 = time.monotonic()
while time.monotonic() - t0 < 4 and not ok:
    ok = ps.server_alive()
    time.sleep(0.1)
print(json.dumps({"alive": ok, "sock": ps.SOCKET_PATH.exists()}))
''' % HOOK_DIR], env={**os.environ, "HOME": _h14}, capture_output=True, text=True, timeout=30)
try:
    _o14 = json.loads(_r14.stdout.strip().splitlines()[-1])
except (ValueError, IndexError):
    _o14 = {"err": (_r14.stderr or _r14.stdout)[-200:]}
check("synth server: a slow first pong is waited for, socket kept",
      _o14.get("alive") is True and _o14.get("sock") is True, str(_o14))
_sh.rmtree(_h14, ignore_errors=True)
# A BUSY server (connection accepted, pong late — PRoot under a cold one-shot synth's load) is
# alive, not dead: calling it dead spawned a rival that SIGTERMed it mid-synth (churn, 12:52-12:56).
_h14b = _tf.mkdtemp(prefix="czh14b-", dir="/tmp")
os.makedirs(os.path.join(_h14b, ".claude", "czytaj-flags"))
_r14b = subprocess.run([sys.executable or "python3", "-c", r'''
import json, os, socket, sys, threading, time
sys.path.insert(0, %r)
import piper_server as ps
ps.RUN_DIR.mkdir(parents=True, exist_ok=True)
s = socket.socket(socket.AF_UNIX); s.bind(str(ps.SOCKET_PATH)); s.listen(4)
ps.PID_FILE.write_text(str(os.getpid()))
def slow():
    while True:
        c, _ = s.accept(); c.recv(256); time.sleep(3); c.sendall(b'{"ok":true}\n'); c.close()
threading.Thread(target=slow, daemon=True).start()
print(json.dumps({"alive": ps.server_alive(), "sock": ps.SOCKET_PATH.exists()}))
''' % HOOK_DIR], env={**os.environ, "HOME": _h14b}, capture_output=True, text=True, timeout=30)
try:
    _o14b = json.loads(_r14b.stdout.strip().splitlines()[-1])
except (ValueError, IndexError):
    _o14b = {"err": (_r14b.stderr or _r14b.stdout)[-200:]}
check("synth server: busy (late pong) counts as alive, not dead",
      _o14b.get("alive") is True and _o14b.get("sock") is True, str(_o14b))
_sh.rmtree(_h14b, ignore_errors=True)

print()
if FAILS:
    print(f"SELFTEST FAILED: {len(FAILS)} check(s) — {', '.join(FAILS)}")
    sys.exit(1)
print("SELFTEST PASSED — all green")
sys.exit(0)
