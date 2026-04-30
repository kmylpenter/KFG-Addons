---
description: Audyt SSOT/DRY (pure audit). Generuje SSOT_DRY_AUDIT_REPORT.md + .ssot-findings.yaml. Args zawezaja zakres (np. /audytssot src/components). Naprawa: /petla solve .ssot-findings.yaml
allowed-tools: [Bash, Read, Write, Grep, Glob, Skill]
---

Uruchom skill **ssot-dry-audit** w cwd. Zakres: `$ARGUMENTS`. Postepuj wedlug 4-fazowego workflow ze SKILL.md (inwentaryzacja → skan → analiza semantyczna → raporty).

Skill jest pure-audit — nie naprawia kodu. Po zakonczeniu wskaz user'owi: `/petla solve .ssot-findings.yaml` dla automatycznej naprawy.
