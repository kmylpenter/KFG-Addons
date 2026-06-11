#!/usr/bin/env python3
# ============================================================================
# merge_skill_rules.py — scala fragment regul skilli do
# ~/.claude/skills/skill-rules.json BEZ kasowania wpisow innych addonow.
#
# Powod (M45/M4): ccv3-polish-translation nadpisywal caly plik (gubiac wpisy
# autoinit-skills: petla/session-init/petla-noc), a autoinit deklarowal je w
# martwym top-level postInstall, ktorego instalator nigdy nie wykonywal.
# Teraz OBA addony SCALAJA swoj fragment -> wynik niezalezny od kolejnosci.
#
# Uzycie: python3 merge_skill_rules.py <fragment.json>
#   fragment moze byc:
#     (a) pelny plik {version, description, skills:{...}}  -> skills scalane
#     (b) plaska mapa {nazwa_skilla: {...}}                -> trafia do skills{}
#   Cel: $SKILL_RULES_PATH albo $CLAUDE_TARGET_BASE/skills/skill-rules.json,
#        inaczej ~/.claude/skills/skill-rules.json.
# ============================================================================
import json, os, sys, tempfile


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def main():
    if len(sys.argv) < 2:
        sys.exit("uzycie: merge_skill_rules.py <fragment.json>")
    frag = load(sys.argv[1])
    if not isinstance(frag, dict):
        sys.exit("  [X] fragment nie jest obiektem JSON")

    base = os.environ.get("CLAUDE_TARGET_BASE") or os.path.expanduser("~/.claude")
    target = os.environ.get("SKILL_RULES_PATH") or os.path.join(base, "skills", "skill-rules.json")

    # wyodrebnij skills z fragmentu (oba ksztalty)
    if isinstance(frag.get("skills"), dict):
        frag_skills = frag["skills"]
        meta = {k: frag[k] for k in ("version", "description") if k in frag}
    else:
        frag_skills = frag
        meta = {}

    cur = load(target)
    if not isinstance(cur, dict):
        cur = {}
    cur.setdefault("version", meta.get("version", "1.0"))
    if "description" not in cur and "description" in meta:
        cur["description"] = meta["description"]
    skills = cur.setdefault("skills", {})

    added = sum(1 for name in frag_skills if name not in skills)
    for name, rule in frag_skills.items():
        skills[name] = rule   # ta sama nazwa: nowsza definicja wygrywa (brak kolizji miedzy naszymi addonami)

    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target))
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cur, f, indent=2, ensure_ascii=False)
    os.replace(tmp, target)
    print(f"  [OK] skill-rules.json: scalono {len(frag_skills)} regul ({added} nowych), razem {len(skills)}")


if __name__ == "__main__":
    main()
