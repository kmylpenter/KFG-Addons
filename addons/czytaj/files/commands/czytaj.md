---
description: Włącz/wyłącz tryb czytania głosowego odpowiedzi (TTS)
allowed-tools: Bash(test:*), Bash(touch:*), Bash(rm:*)
---

!`if [ -f ~/.claude/czytaj.flag ]; then rm -f ~/.claude/czytaj.flag; echo "OFF"; else touch ~/.claude/czytaj.flag; echo "ON"; fi`

Powyższa komenda przełączyła tryb czytania głosowego.

Jeśli wynik to **ON** — odpowiedz wyłącznie: "Tryb czytania włączony — odpowiedzi będą krótsze i odczytywane przez TTS."

Jeśli wynik to **OFF** — odpowiedz wyłącznie: "Tryb czytania wyłączony."

Nie wykonuj żadnych innych akcji ani analiz. Tylko jednolinijkowa odpowiedź.
