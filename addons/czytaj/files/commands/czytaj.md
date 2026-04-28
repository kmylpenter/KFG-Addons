---
name: czytaj
description: Toggle voice reading mode
---

!`if [ -f ~/.claude/czytaj.flag ]; then rm -f ~/.claude/czytaj.flag; pkill -9 -f piper_server >/dev/null 2>&1; pkill -9 -f piper-daemon >/dev/null 2>&1; pkill -9 -f paplay >/dev/null 2>&1; echo "OFF"; else touch ~/.claude/czytaj.flag; nohup python3 "$HOME/.claude/hooks/czytaj/piper_server.py" serve >/dev/null 2>&1 & disown; echo "ON"; fi`
