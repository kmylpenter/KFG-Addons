---
name: czytaj
description: Toggle voice reading mode (TTS hands-free). Handled entirely by the czytaj UserPromptSubmit hook (toggle.sh + block) — no model turn.
---

Przełącznik /czytaj powinien zostać obsłużony przez hook czytaj (user-prompt-submit.sh) bez udziału modelu. Jeśli to widzisz, hook nie zadziałał — odpowiedz jednym zdaniem: „Przełącznik czytaj nie zadziałał, sprawdź hook user-prompt-submit.”
