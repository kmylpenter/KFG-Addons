#!/data/data/com.termux/files/usr/bin/bash
# Czytaj — Termux installer.
# Copies hook scripts + skill into ~/.claude/, validates Piper runtime,
# patches ~/.claude/settings.json idempotently with timestamped backup.

set -e

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
PIPER_HOME="${PIPER_HOME:-$HOME/piper-tts}"

OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
case "$OS_NAME" in
  Linux*)
    if [ ! -d /data/data/com.termux ]; then
      echo "  [X] To jest addon TYLKO dla Termux na Androidzie."
      echo "      Linux/Mac/Windows wymagają osobnego instalatora (TODO)."
      exit 1
    fi
    ;;
  *)
    echo "  [X] Nieobsługiwany system: $OS_NAME"
    exit 1
    ;;
esac

echo ""
echo "==> Instalacja addonu: czytaj"
echo ""

# --- Dependency probes ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "  [X] BRAK: python3 (wymagany). Zainstaluj: pkg install python"
  exit 1
fi

WARN_PIPER=0
if [ ! -x "$PIPER_HOME/piper1-gpl/libpiper/piper" ]; then
  echo "  [!] BRAK: $PIPER_HOME/piper1-gpl/libpiper/piper (binarka)"
  WARN_PIPER=1
fi
if [ ! -f "$PIPER_HOME/piper1-gpl/libpiper/install/lib/libpiper.so" ]; then
  echo "  [!] BRAK: libpiper.so (zbuduj wg gyroing/piper-tts-for-termux)"
  WARN_PIPER=1
fi
if [ ! -d "$PIPER_HOME/piper1-gpl/libpiper/install/espeak-ng-data" ]; then
  echo "  [!] BRAK: espeak-ng-data"
  WARN_PIPER=1
fi
if ! ls "$PIPER_HOME/voices/"*.onnx >/dev/null 2>&1; then
  echo "  [!] BRAK: głosów (.onnx) w $PIPER_HOME/voices/"
  echo "      Pobierz np.: pl_PL-gosia-medium z huggingface.co/rhasspy/piper-voices"
  WARN_PIPER=1
fi
if [ "$WARN_PIPER" = "1" ]; then
  echo "  [!] Piper niekompletny — TTS będzie próbować fallback przez termux-tts-speak."
  echo "      Aby zbudować Piper: zobacz README addonu czytaj."
fi

if ! command -v termux-tts-speak >/dev/null 2>&1; then
  echo "  [!] BRAK: termux-tts-speak"
  echo "      Wymaga: pkg install termux-api ORAZ aplikacji Termux:API z F-Droid"
  echo "      (nie z Google Play — to musi być wersja F-Droid)"
fi

if ! command -v paplay >/dev/null 2>&1; then
  echo "  [!] BRAK: paplay (PulseAudio). Zainstaluj: pkg install pulseaudio"
fi

# --- Copy files ---
mkdir -p "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks/czytaj" "$CLAUDE_DIR/skills/czytaj"

cp "$ADDON_DIR/files/commands/czytaj.md" "$CLAUDE_DIR/commands/"
chmod 644 "$CLAUDE_DIR/commands/czytaj.md"
echo "  [OK] commands/czytaj.md"

# Use cp -P (no symlink follow) and explicit file list to avoid orphan files
# from previous installs surviving. We sync a clean snapshot.
HOOK_SRC="$ADDON_DIR/files/hooks/czytaj"
HOOK_DST="$CLAUDE_DIR/hooks/czytaj"
for f in _speak.py piper_server.py piper_stream.py pre-tool-use.py pre-tool-use.sh \
         stop.py stop.sh user-prompt-submit.sh toggle.sh silent.wav preheat.wav; do
  if [ -f "$HOOK_SRC/$f" ]; then
    cp -P "$HOOK_SRC/$f" "$HOOK_DST/$f"
  fi
done
chmod 700 "$HOOK_DST"
chmod 644 "$HOOK_DST/"*.py "$HOOK_DST/"*.wav 2>/dev/null || true
chmod 755 "$HOOK_DST/"*.sh 2>/dev/null || true
echo "  [OK] hooks/czytaj/ (synced)"

# --- Skill ---
if [ -f "$ADDON_DIR/files/skills/czytaj/SKILL.md" ]; then
  cp "$ADDON_DIR/files/skills/czytaj/SKILL.md" "$CLAUDE_DIR/skills/czytaj/SKILL.md"
  chmod 644 "$CLAUDE_DIR/skills/czytaj/SKILL.md"
  echo "  [OK] skills/czytaj/SKILL.md"
fi

# --- Stale state cleanup (allow safe re-install) ---
rm -f "$HOME/.claude/czytaj.flag" "$HOME/.claude/czytaj-state.json"
PIPER_RUN="${TMPDIR:-/tmp}/piper-server"
[ -d "$PIPER_RUN" ] && rm -rf "$PIPER_RUN"
pkill -9 -f piper_server >/dev/null 2>&1 || true
pkill -9 -f piper-daemon >/dev/null 2>&1 || true

# --- settings.json patch (atomic, with backup) ---
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.czytaj.bak.$(date +%s)"
else
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" <<'PY'
import json, os, sys, tempfile
path = sys.argv[1]
try:
    with open(path) as f:
        s = json.load(f)
    if not isinstance(s, dict):
        raise ValueError("settings.json is not a JSON object")
except (json.JSONDecodeError, ValueError) as e:
    print(f"  [!] settings.json malformed ({e}) — start fresh skeleton")
    s = {}

s.setdefault("hooks", {})

ups_cmd = "bash $HOME/.claude/hooks/czytaj/user-prompt-submit.sh"
stop_cmd = "bash $HOME/.claude/hooks/czytaj/stop.sh"
pre_cmd = "bash $HOME/.claude/hooks/czytaj/pre-tool-use.sh"


def has_cmd(event, cmd):
    for entry in s["hooks"].get(event, []):
        for h in entry.get("hooks", []):
            if h.get("command") == cmd:
                return True
    return False


def add_hook(event, cmd, label, matcher=""):
    if has_cmd(event, cmd):
        print(f"  [--] settings.json: {label} już istnieje")
        return
    s["hooks"].setdefault(event, []).append({
        "matcher": matcher,
        "hooks": [{"type": "command", "command": cmd, "timeout": 10}],
    })
    print(f"  [OK] settings.json: dodano {label}")


add_hook("UserPromptSubmit", ups_cmd, "UserPromptSubmit hook")
add_hook("Stop", stop_cmd, "Stop hook")
add_hook("PreToolUse", pre_cmd, "PreToolUse hook")

# Atomic write so a heredoc crash mid-dump can't truncate the file.
fd, tmp_path = tempfile.mkstemp(prefix=".settings-", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w") as f:
        json.dump(s, f, indent=2, ensure_ascii=False)
    os.replace(tmp_path, path)
    os.chmod(path, 0o600)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
PY

echo ""
echo "==> Gotowe"
echo ""
echo "Komenda:"
echo "  /czytaj   — toggle trybu czytania (skill)"
echo ""
if [ "$WARN_PIPER" = "1" ]; then
  echo "  Uwaga: Piper niekompletny. Patrz README/audyt jak go zbudować."
fi
