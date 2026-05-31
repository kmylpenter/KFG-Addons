# czytaj fix — on-device deploy & verification (2026-05-31)

The `/petla solve` of the 50-finding audit landed on branch **`fix/czytaj-audit-2026-05-31`**
as 13 per-fix-group commits (bisectable, revertible). The repo working tree is fixed; the
LIVE installed hooks (`~/.claude/hooks/czytaj/`) were **deliberately NOT touched** — many fixes
affect audio/activation and can only be *confirmed* on the tablet. This is the deploy + verify
runbook. Baseline to roll back to = the installed copy as it is now (pre-deploy, audibly working).

## 0. Review the branch
```bash
git -C /root/projekty/KFG-Addons log --oneline main..fix/czytaj-audit-2026-05-31
git -C /root/projekty/KFG-Addons diff main..fix/czytaj-audit-2026-05-31 -- addons/czytaj
```

## 1. Static gate (no audio needed — run before deploying)
```bash
cd /root/projekty/KFG-Addons/addons/czytaj/files/hooks/czytaj
python3 -m py_compile *.py && echo PYCOMPILE_OK
for s in *.sh; do bash -n "$s" && echo "bashn $s OK"; done
# per-project: NO functional global-flag gate may remain (only install.sh migration rm + comments)
grep -rn 'czytaj\.flag' . ../../../install.sh
# sha1 parity bash↔python (MUST match):
export CLAUDE_PROJECT_DIR=/root/projekty/KFG-Addons
printf '%s' "$(realpath "$CLAUDE_PROJECT_DIR")" | sha1sum | cut -d' ' -f1
PYTHONPATH=. python3 -c "import _speak,os;print(os.path.basename(_speak._project_flag('')).removesuffix('.flag'))"
# ^ the two hashes must be identical.
```

## 2. Deploy to the live hooks
```bash
SRC=/root/projekty/KFG-Addons/addons/czytaj/files/hooks/czytaj
DST=~/.claude/hooks/czytaj
cp "$SRC"/*.py "$SRC"/*.sh "$DST"/
chmod +x "$DST"/*.sh          # F8 — the bare cp can drop +x
# skill + commands (per-project wording, manifest):
cp /root/projekty/KFG-Addons/addons/czytaj/files/skills/czytaj/SKILL.md ~/.claude/skills/czytaj/
cp /root/projekty/KFG-Addons/addons/czytaj/files/commands/{czytaj,pauza}.md ~/.claude/commands/
# F16 — optional hygiene: drop stale pre-PRoot bytecode (ASK yourself first; harmless):
#   rm -f "$DST"/__pycache__/*.cpython-312.pyc
```
NOTE: migration — reading mode is now per-project, so the OLD global `~/.claude/czytaj.flag`
no longer activates anything. Run `/czytaj` ONCE in each project you want reading on.

## 3. On-device verification (the part that needs your ears)
Verify in this order; each maps to a fix group. STOP and report if any fails.

1. **CLAUDE_PROJECT_DIR is exported into hooks** (the whole per-project key rests on it):
   add `echo "PROJDIR=$CLAUDE_PROJECT_DIR pwd=$PWD" >> ~/.claude/czytaj.log` temporarily to
   stop.sh, fire a Stop hook, and confirm `CLAUDE_PROJECT_DIR` is non-empty. If it's empty,
   the per-project key falls back to `$PWD`/`data['cwd']` (usually fine, but confirm).
2. **per-project activation** (F1/F2/F18 — the highest-risk fix):
   - In project A: `/czytaj` → expect `Tryb czytania włączony.` AND on the next reply you
     HEAR audio. Confirm `~/.claude/czytaj-flags/<key>.flag` was created.
   - Open project B (no `/czytaj`) → B must stay SILENT.
   - `/czytaj` OFF in A → A silent; a still-ON project keeps reading. (If reading never
     activates → silent-everywhere = the per-project key mismatch; check step 1 + parity.)
3. **channel arbitration** (F3/F6/F7 — 2 windows, one speaker):
   - Active window talking + a background window finishes a turn → background must NOT cut
     off the active one (look for `CHANNEL yield-busy` / `EXIT channel-yield` in czytaj.log).
   - Lone single window → must speak EVERY turn (no new silence, no `channel-yield` line).
4. **tempo** (F9): after deploy, check `<piper> --help` lists one of `--length-scale` /
   `--length_scale` / `--length` (whichever it is, the probe auto-uses it). Listen — tempo
   should be faster (≈0.6 length-scale). If `--help` lists none, tempo stays as-is (no break).
5. **mic / BUG A** (F10) — needs the Voice Typer keyboard side first:
   hand `thoughts/shared/petla/voice-typer-recording-flag-CONTRACT.md` to the Claude that
   maintains the keyboard. Once it writes `/sdcard/Download/Termux-flags/voice-typer-recording.flag`
   (heartbeat epoch, refreshed ≤1s), test: start dictation while TTS is talking → TTS stops
   within ~0.3s; stop dictation → next reply speaks. Crash the keyboard mid-dictation → TTS
   resumes within ~3s (stale heartbeat self-heal).
6. **encoding** (F22/F23): a reply with Polish diacritics + a fenced code block reads cleanly
   (no crash, no code/backticks spoken, `a*b*c` not fused to `abc`).

## 4. Rollback (per group — there is no automated audio test)
Each fix group is its own commit. If a group regresses, revert just that commit:
```bash
git -C /root/projekty/KFG-Addons revert <commit-sha>   # then re-deploy step 2
```
Full rollback: `git checkout` the pre-deploy installed copies, or reinstall the prior version.

## Commit map (branch fix/czytaj-audit-2026-05-31)
docs → observability(F13) → robustness(F14/22/23/31/41/42/45/46/47) →
text-sanitization(F26/28/29/30) → deploy-hygiene(F8/38/49) →
setup-provisioning(F24/25/35/36/37/44) → **per-project(F1/2/4/5/15/18/32/40/50)** →
**channel-lock(F3/6/7/43)** → process-mgmt+path(F21/33/34/11) → daemon-runtime(F19/20) →
mic-detection(F10/27/48) → tempo(F9). (F12/F16/F17 = documented no-ops/deferred.)

## 5. Session-2 additions (rish PRoot fix + volume-key control)
NOT part of the 50-finding audit — added after, same branch working tree. New/changed files:
`volume_watcher.py` (new), `_speak.py` (4 new fns at end: stop_now / speak_text_now /
_resolve_active_transcript / read_last_message), `toggle.sh` (watcher spawn + OFF teardown),
`setup-shizuku.sh` (idempotent rish patch). Deploy: the `cp "$SRC"/*.py "$SRC"/*.sh` in step 2
already carries them.

**rish PRoot fix** — stock rish aborts under PRoot fake-root (`[ -w $DEX ]` is always true → `exit 1`
*before* app_process, which actually loads the dex fine on Android 14–16; it checks real mode bits,
not fake-root `access()`). The fix lives in the live `~/.shizuku/rish`; to (re)apply on a fresh env
just re-run setup-shizuku.sh — it now patches the freshly-extracted rish idempotently:
```bash
bash ~/.claude/hooks/czytaj/setup-shizuku.sh   # expect: [OK] rish PRoot fake-root patch applied + [OK] uid=shell
rish -c id                                      # must print uid=2000(shell)
```
GOTCHA: SELinux=Enforcing blocks WRITE to /dev/input → `sendevent` / `input keyevent` can't generate
test events; only PHYSICAL keys produce getevent events. getevent READ works (standard adb path).

**Volume-key control** (needs rish working + Shizuku ready):
- Watcher auto-starts on `/czytaj` ON (toggle.sh), single-instance flock, reads gpio_keys via getevent.
- **Volume Down = stop TTS now**, **Volume Up = re-read Claude's last message.**
- Keys still change system volume (passive getevent; consuming would need EVIOCGRAB). Gated to czytaj-ON.
Verify (no ears needed):
```bash
pgrep -af '[v]olume_watcher'                 # exactly 1 process while reading is ON
grep VOLKEY ~/.claude/czytaj.log | tail      # 'watcher start' + 'reading /dev/input/eventN'
```
On-device (ears): press **Volume Up** → hears the last message re-read; press **Volume Down** mid-read
→ instant silence. If a press logs NO `VolumeUp/Down` line → getevent isn't delivering (pipe buffering
or wrong device); if it logs but stays silent → audio path. Toggle OFF (last project) kills the
watcher + `rish -c "pkill -9 getevent"` reaps the Shizuku-side reader.
