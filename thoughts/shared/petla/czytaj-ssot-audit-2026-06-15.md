# czytaj — SSOT audit (speed + reliability lens), 2026-06-15

**Scope:** the `czytaj` addon under `addons/czytaj/files/hooks/czytaj/` (the read-back / TTS
hook chain). **Mode:** PURE AUDIT — findings only, nothing fixed. Remediation belongs to a
separate pass (`/petla solve thoughts/shared/petla/czytaj-ssot-findings-2026-06-15.yaml`,
ideally in a fresh window).

**Method:** targeted manual SSOT/DRY read (not the generic `/audytssot` magic-number sweep),
because the speed/reliability story here is about **cross-file, cross-language duplication of
the same fact** — paths, daemon location, config defaults, the project key — kept aligned by
hand-maintained "MUST match" comments. A generic sweep would surface constant noise and miss
exactly this. Every claim below is ✓ VERIFIED against the file:line cited.

---

## TL;DR — the one story

czytaj has **no single source of truth for its runtime paths or config.** Each of the 3 core
executables (`_speak.py`, `piper_server.py`, `piper_stream.py`) and `volume_watcher.py` plus 5
shell scripts **re-declares the same paths and defaults as literals**, in two languages, and the
code itself documents the fragility with **8 "MUST match X" / "mirror of Y" / "kept in sync"
comments**. This is not cosmetic: this exact class of bug already produced czytaj's worst latency
problem — the `RUN_DIR` daemon-split that made synth **always cold (~3–7 s)**. The fix back then
was to hardcode the value identically in 3 spots; the duplication (now 3 sources) survived.

The highest-leverage remediation is a single small shared module (`czytaj_paths.py` for Python,
sourced/queried by the shell scripts) that dissolves findings **S1, S2, S4, S5** and the Python
half of **S3** at once. That turns the historical daemon-split bug from "prevented by vigilance"
into "structurally impossible."

**Good news first — these were OPEN in the 2026-06-03 latency audit and are now FIXED** (so you
don't re-chase them):

| Prior issue | Status now | Evidence |
|---|---|---|
| tmux active-window probe uncached (~0.4 s/press) | ✅ cached, TTL 2.5 s | `_speak.py:1367-1384` |
| auto-read's wav deleted, re-read = re-synth | ✅ saved into read-back cache | `_speak.py:1626-1652`, `:1187`, `:1741` |
| cache wav lands in a different dir than read-back looks in | ✅ both key on `basename(transcript)` | save `_speak.py:1187/1725`, read `:1725/1741` |
| daemon idle-timeout kills warmth mid-session | ✅ idle-off while any flag exists | `piper_server.py:417` |
| auto-read guard probes serial (~9 s) | ✅ parallelized | commit `99a262f` |

What remains is mostly **latent reliability landmines** (duplication that is currently aligned but
one careless edit from breaking) plus **one still-open speed item** (S6) carried from last audit.

---

## Findings

Severity: **HIGH** = severe blast radius if it drifts (silent skill death / always-cold synth) or
an active speed cost; **MED** = subtle corruption / DRY debt with real drift vectors; **LOW** =
hygiene / minor.

### S1 — HIGH (reliability). No shared paths module; state-file paths re-declared in 8 files, 2 languages.
There is **no `paths.py`/`config.py`** in the addon (verified by directory listing). Every script
hardcodes the paths it touches:
- `FLAG_DIR` (the on/off gate dir) in **7 places**: `_speak.py:18`, `piper_server.py:50`,
  `volume_watcher.py:38`, `toggle.sh:6`, `user-prompt-submit.sh:29`, `pre-tool-use.sh:7`, `stop.sh:7`.
- `czytaj.log` in **4**: `_speak.py:22`, `piper_stream.py:496`, `piper_server.py:195`, `user-prompt-submit.sh:6`.
- `KEYPAUSE_STATE` in **3**: `piper_stream.py:123`, `volume_watcher.py:103`, `user-prompt-submit.sh:39`.
- `SHIZUKU_FLAG` in **3**: `_speak.py:26`, `volume_watcher.py:39`, `setup-shizuku.sh:27`.
- `PLAYING_MARKER` in **2**: `piper_stream.py:129`, `volume_watcher.py:109` (commented "MUST match volume_watcher.py").

**Impact:** a writer and a reader of the same file can silently disagree after any rename (e.g.
the pause flag is written but never read → pause stops working with no error). The blast radius is
the whole skill, because `FLAG_DIR` is the activation gate. Currently aligned → **latent**.
*(Note: the small Python hooks `precache.py`, `stop.py`, `pre-tool-use.py` are CLEAN — they
`from _speak import …` instead of re-declaring. The debt is concentrated in the 3 core files +
shell, which have nothing to import from.)*

### S2 — HIGH (reliability + speed). `RUN_DIR` (daemon socket dir) hardcoded in 3 places, sync-by-comment.
Literal `~/.cache/czytaj/piper-server` in `piper_server.py:57`, `toggle.sh:5`, `install.sh:115` —
each annotated "FIXED path, SSOT with [the others]". The annotation is the tell: it is the
**opposite** of SSOT (three sources kept aligned by a human).

**Impact:** this is the exact value whose earlier env-derived divergence split the daemon across
processes → the socket was never shared → **synth was ALWAYS cold (~3–7 s)** — czytaj's headline
latency complaint. The current hardcoding prevents the env-derivation form, but if anyone edits
one copy (e.g. moves to `XDG_RUNTIME_DIR`), the split returns and synth silently goes cold again.
**Highest-value consolidation:** one shared definition makes the regression structurally impossible.

### S3 — HIGH (reliability). Per-project key (sha1 of realpath) derived in 3 places, 2 languages, "MUST match EXACTLY".
- Python: `_speak.py:128-129` — `hashlib.sha1(os.path.realpath(_project_dir(cwd)).encode()).hexdigest()`.
- Shell: `toggle.sh:12` and `user-prompt-submit.sh:28` — `printf '%s' "$(realpath "$DIR")" | sha1sum`.

**Impact:** this key decides *whether reading is on for this project*. If the three derivations
drift, `/czytaj` writes a flag under a key the hooks compute differently → hooks never find it →
**reading silently never activates (or activates in the wrong window)** — the skill looks dead with
no error. Real, already-latent drift vectors: Python `_project_dir` = `CLAUDE_PROJECT_DIR or cwd or
getcwd()` vs shell `${CLAUDE_PROJECT_DIR:-$PWD}` diverge when the var is **empty-string vs unset**;
`os.path.realpath` vs coreutils `realpath` symlink semantics must stay identical. Currently aligned
→ **latent**, but the highest-stakes of the latent set (it gates everything).

### S4 — MED (maintainability). Piper install-location resolver duplicated 3×; PIPER_* paths 2×.
`_resolve_piper_home()`/`_resolve_piper_bin()` copy-pasted (same docstring) in `piper_server.py:30-49`,
`piper_stream.py:24-43`, `_speak.py:66-84`. `PIPER_HOME/PIPER_LIB/PIPER_ESPEAK/PIPER_VOICES` are
recomputed identically in `piper_server.py` and `piper_stream.py`.

**Impact:** the next HOME/install-layout migration (this device already migrated Termux→PRoot once,
which is *why* the multi-home fallback exists) must be fixed in 3 functions; miss one and that entry
point logs `missing-piper` and stays silent. Pure DRY debt; **latent**.

### S5 — MED (reliability). Synth config defaults duplicated across server and stream.
- `PIPER_VOICE="pl_PL-gosia-medium"`: `piper_server.py:61`, `piper_stream.py:44`.
- sample rate `22050`: `piper_server.py:64,66`, `piper_stream.py:46,48`.
- `length_scale 0.6`: `piper_server.py:62`, `piper_stream.py:97,247`.
- `VOICE_TYPER_STALE_S=3.0`: `piper_stream.py:63`, `_speak.py:103` (commented "mirror of _speak.py").

**Impact:** the daemon synthesizes with one set, the stream client assumes another if they drift →
wrong sample rate = garbled/wrong-pitch audio that's hard to trace to a config split. **Latent.**

### S6 — MED (speed, STILL OPEN from 2026-06-03). `server_alive()` trusts socket-connect, not an app-level PING.
`piper_server.py:101-124` → `_can_connect()` (`:84-98`) only does `socket.connect()`. A daemon that
is **bound but wedged** passes the liveness check, so the client proceeds and the synth silently
takes the **cold path (~3–7 s)** instead of warm (~1 s). The prior audit (Agent 1, finding 1)
recommended a `{"ping":1}`→`{"ok":true}` round-trip with a ~0.3 s timeout; **not implemented.**
This is "the single source of truth for *is the daemon alive* is a proxy (socket reachable), not the
real signal (daemon responds)." Adjacent to SSOT, squarely a **speed** item, and the only OPEN
performance regression class remaining.

### S7 — LOW (drift). `setup-shizuku.sh`: runtime copy is stale vs repo (missing the M51 anchor-verify guard).
`diff` of repo vs `~/.claude/hooks/czytaj/setup-shizuku.sh`: the repo has the `|| exit 1` abort and
the M51 sentinel check (repo lines 57, 83-89) that refuses to symlink an unverified `rish`; the
**runtime copy lacks both** (install.sh hasn't been re-run since commit `e104376`). All other `.py`/
`.sh` files are byte-identical repo↔runtime (verified).

**Impact:** the *live* setup script would symlink an unverified privileged relay — the exact failure
M51 was added to prevent. It is a one-time setup path, **not** the read-back hot path, so LOW for
speed; but it is a concrete "two copies, the runtime one is stale" SSOT/drift finding. Fix = re-run
`install.sh` (or treat repo as the only source and stop hand-editing runtime).

### S8 — LOW (speed). Cache-HIT read-back still forks a fresh `python3` per press.
`read_message_back` → `_play_cached` (`_speak.py:1663`) → `subprocess.Popen([python3, PIPER_STREAM])`
with `CZYTAJ_PLAY_WAV`. ~250–300 ms interpreter spawn on every scrub press, even on a HIT.
`volume_watcher.py` already imports `_speak` in-process (`:36`), so an in-process play of the cached
wav is feasible. Flagged at the prior audit (Agent 2, finding 4); still a fork. Minor; not SSOT.

---

## Recommended remediation direction (NOT done — proportionate, one pass)

1. **`czytaj_paths.py`** — one module that owns every `~/.claude/czytaj-*` path, `RUN_DIR`,
   `FLAG_DIR`, `LOG_FILE`, and the synth defaults (voice/rate/length/staleness). `_speak.py`,
   `piper_server.py`, `piper_stream.py`, `volume_watcher.py` import from it. Dissolves S1 (Python
   half), S2 (Python half), S4, S5. ~1 small file; no abstraction layer, no config framework.
2. **One canonical project-key function**, exported from that module, and a `czytaj-env.sh` the
   shell scripts `source` (or have them call `python3 -m czytaj_paths key`) so `RUN_DIR`, `FLAG_DIR`
   and the sha1 key have **one** definition the shell reads instead of re-deriving. Closes the
   cross-language half of S2 and all of S3 — the highest-stakes landmine.
3. **`server_alive()` PING** (S6) — the only OPEN speed regression; ~0.3 s round-trip, removes the
   silent cold-fallback class.
4. S7 (re-run install / stop hand-editing runtime) and S8 (in-process cached play) are LOW — batch
   them or defer.

Order by leverage: **2 → 1 → 3** are the reliability/speed wins; 4 is hygiene.

---

## Honesty footer
- **Verified vs inferred:** every file:line above was read this session; the "FIXED since 2026-06-03"
  table was confirmed in the current code, not assumed from the handoff.
- **Did NOT touch:** any code (pure audit). No `/audytssot` skill run — replaced by this targeted
  pass for the reasons in Method.
- **Out of scope / not findings:** install.sh's Termux-only shebang+guard (intentional for the
  target; cross-platform is handled at the `install-addons.sh` level), and the ~1.6–1.9 s
  `termux-media-player` playback floor (structural, no PulseAudio — documented, not an SSOT issue).
- **Residual risk I could not fully discharge:** the multi-window-**same-project-dir** case, where
  `_transcript_for_project` returns most-recent-by-mtime and two windows share a dir — read-back may
  resolve the other window's last turn. It is an inherent "resolve by project dir" ambiguity, not a
  duplicate-source bug, so it's noted here rather than filed as a finding.
