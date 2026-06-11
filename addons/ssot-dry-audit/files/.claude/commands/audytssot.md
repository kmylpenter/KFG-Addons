---
description: Audyt SSOT/DRY (pure audit). Generuje SSOT_DRY_AUDIT_REPORT.md + .ssot-findings.yaml + wywiad decyzyjny (AUQ). Args zawezaja zakres (np. /audytssot src/components). Naprawa: /petla solve .ssot-findings.yaml (najlepiej w nowym oknie)
allowed-tools: [Bash, Read, Write, Grep, Glob, Skill, AskUserQuestion]
---

Uruchom skill **ssot-dry-audit** w cwd. Zakres: `$ARGUMENTS`. Postepuj wedlug 5-fazowego workflow ze SKILL.md (inwentaryzacja → skan → analiza semantyczna → raporty → wywiad decyzyjny AskUserQuestion + update artefaktow).

Skill jest pure-audit — nie naprawia kodu. Po zakonczeniu (i po wywiadzie) wskaz user'owi: `/petla solve .ssot-findings.yaml` dla automatycznej naprawy — najlepiej w NOWYM oknie konwersacji (handoff niesie komplet).
