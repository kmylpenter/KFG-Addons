#!/data/data/com.termux/files/usr/bin/bash
# Czytaj — Termux installer
# Copies files to ~/.claude/ and patches settings.json with hooks.

set -e

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo ""
echo "==> Instalacja addonu: czytaj"
echo ""

if ! command -v termux-tts-speak >/dev/null 2>&1; then
  echo "  [!] BRAK: termux-tts-speak"
  echo "      Zainstaluj: pkg install termux-api"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "  [X] BRAK: python3 (wymagany)"
  exit 1
fi

mkdir -p "$CLAUDE_DIR/commands"
cp "$ADDON_DIR/files/commands/czytaj.md" "$CLAUDE_DIR/commands/"
echo "  [OK] commands/czytaj.md"

mkdir -p "$CLAUDE_DIR/hooks/czytaj"
cp -r "$ADDON_DIR/files/hooks/czytaj/"* "$CLAUDE_DIR/hooks/czytaj/"
chmod +x "$CLAUDE_DIR/hooks/czytaj/"*.sh
echo "  [OK] hooks/czytaj/"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)

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
    if not has_cmd(event, cmd):
        s["hooks"].setdefault(event, []).append({
            "matcher": matcher,
            "hooks": [{"type": "command", "command": cmd, "timeout": 5}],
        })
        print(f"  [OK] settings.json: dodano {label}")
    else:
        print(f"  [--] settings.json: {label} juz istnieje")

add_hook("UserPromptSubmit", ups_cmd, "UserPromptSubmit hook")
add_hook("Stop", stop_cmd, "Stop hook")
add_hook("PreToolUse", pre_cmd, "PreToolUse hook")

with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
PY

echo ""
echo "==> Gotowe"
echo ""
echo "Komenda:"
echo "  /czytaj    — toggle trybu czytania (on/off)"
echo ""
echo "Test:"
echo "  termux-tts-speak -l pl-PL \"test\""
echo ""
