# SSOT/DRY Audit (pure-audit)

Skill audytujacy kod pod katem **Single Source of Truth (SSOT)** i **Don't Repeat Yourself (DRY)**.

**v2.0 — pure audit**: skill generuje raport i konczy. Naprawe deleguje do `/petla solve` (single responsibility, match z CLAUDE.md "audit vs fix mode").

## Instalacja

```bash
bash install.sh
```

Wymaga `python3` 3.10+ (Termux: `pkg install python`).

## Uzycie

```bash
/audytssot                  # caly projekt w cwd
/audytssot src/components   # zawezony zakres
```

Lub naturalne frazy: "zrob audyt SSOT", "znajdz duplikaty w kodzie", "sprawdz spojnosc kodu", "redundancja w kodzie".

## Output

Dwa pliki w roocie projektu (oba **auto-gitignored**):

| Plik | Cel |
|------|-----|
| `SSOT_DRY_AUDIT_REPORT.md` | Czytelny raport dla czlowieka |
| `.ssot-findings.yaml` | Maszynowy handoff dla `/petla solve` |

Po audycie:

```bash
/petla solve .ssot-findings.yaml      # automatyczna naprawa (HIGH=auto, MEDIUM=ask, LOW=skip)
# lub recznie z markdown
```

## Workflow (4 fazy)

1. **Inwentaryzacja** — typ projektu (walks up tree), zakres (auto/zawezony)
2. **Skan mechaniczny** — helper Python z 6 kategoriami:
   - duplicate strings (escape-aware, template literals, redacted secrets)
   - duplicate numbers (decimal-aware, np. 0.23 VAT)
   - duplicate function names (Python/JS/Go/Kotlin/Rust + GAS)
   - duplicate type names (interface/type/class/struct/enum)
   - duplicate code blocks (sha256, sliding window 5 linii)
   - **Polish business IDs** (PESEL/NIP/REGON/IBAN — zawsze critical, RODO)
3. **Analiza semantyczna** — duplicate state, derived state, shotgun surgery, niespojne zrodla, **Polish-business pack** (Zoho field SSOT, currency/date formats, VAT, multi-tenant)
4. **Raporty** — sanityzacja PII, auto-gitignore, atomic write markdown + YAML handoff

## Confidence rating

Kazde finding dostaje **HIGH/MEDIUM/LOW**:

| Pewnosc | /petla solve robi |
|---------|---------------------|
| HIGH | auto-fix |
| MEDIUM | per-finding user confirmation |
| LOW | POMIN, zostaw pytanie |

## Filozofia

- **Single responsibility** — pure audit, naprawe deleguj
- **Ryzyko biznesowe > liczba wystapien**
- **Polish-business native** — PESEL/NIP/REGON/IBAN/VAT/RODO awareness wbudowane
- **PII safety** — secrets pre-redacted w helperze, raport sanitized przed zapisem
- **Filtruj false positives** — GAS API namespaces, testy/mocki, i18n, migracje wykluczone
- **Atomic writes** — `.tmp + mv`, zabezpieczenie przed corrupted output

## Pliki addonu

```
addons/ssot-dry-audit/
├── addon.json
├── install.sh
├── README.md
└── files/
    └── .claude/
        ├── commands/
        │   └── audytssot.md             # slash command (single-line invocation)
        └── skills/
            └── ssot-dry-audit/
                ├── SKILL.md             # 4-fazowy workflow + zasady
                └── scripts/
                    └── detect_duplicates.py  # helper Python v2.0
```

## Co skill robi i czego NIE robi

| Robi | NIE robi |
|------|----------|
| Audyt + raport markdown | Naprawia kod (to robi /petla solve) |
| Sanityzuje PII przed zapisem | Commituje cokolwiek |
| Auto-gitignore raporty | Tworzy branch refaktoru |
| Generuje YAML handoff | Modyfikuje pliki w `src/` |
| Filtruje GAS boilerplate | Zglasza false positives z testow |
| Wykrywa Polish PII (RODO) | Pisze raw PESEL/IBAN do raportu |

## Migracja z v1.x

Stary command `/naprawssot` zostanie usuniety przez `install.sh` automatycznie. Stary plik `~/.claude/skills/ssot-dry-audit/` zostanie zbackupowany do `*.bak.<timestamp>` przed nadpisaniem.

## Helper schema

`detect_duplicates.py` v2.0 produkuje JSON ze `schema_version: "2.0"`. Skill waliduje schema przed konsumpcja. Helper exit codes: 0=ok, 1=invalid args, 2=path traversal.
