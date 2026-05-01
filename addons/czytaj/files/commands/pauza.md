---
name: pauza
description: Pause/resume TTS (czytaj) for 60 seconds. Toggle — second invocation resumes immediately.
---

!`if [ -f ~/.claude/czytaj-pause.flag ]; then rm -f ~/.claude/czytaj-pause.flag; echo "WZNOWIONE"; else echo "$(($(date +%s) + 60))" > ~/.claude/czytaj-pause.flag; echo "PAUZA-60S"; fi`
