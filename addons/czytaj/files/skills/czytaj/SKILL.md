---
name: czytaj
description: Toggle voice reading mode (TTS hands-free). Triggers when user says "czytaj", "/czytaj", "włącz czytanie", "wyłącz czytanie", "tryb głosowy".
version: "1.1"
user-invocable: true
allowed-tools: Bash
---

Run `bash ~/.claude/hooks/czytaj/toggle.sh` once. If output is `ON` reply exactly `Tryb czytania włączony.` If `OFF` reply exactly `Tryb czytania wyłączony.` Nothing else.
