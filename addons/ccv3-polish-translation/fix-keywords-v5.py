#!/usr/bin/env python3
"""
Fix v5: Add intentPatterns for generic Polish words.

Instead of full phrase keywords like "sprawdz jakość kodu",
use regex patterns like "sprawdz.*(jakość|lint)" for better matching.
"""

import json
from pathlib import Path

V4_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules-v4.json"
V5_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules-v5.json"

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(data, path):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=4, ensure_ascii=False)

# Remove full-phrase keywords, use intentPatterns instead
KEYWORDS_TO_REMOVE = {
    "qlty-check": [
        "sprawdz jakosc kodu",
        "sprawdź jakość kodu",
        "sprawdz linting",
    ],
    "test": [
        "sprawdz testy",
        "sprawdź testy",
    ],
    "review": [
        "sprawdz PR",
        "sprawdź PR",
        "sprawdz zmiany w PR",
    ],
    "security": [
        "sprawdz bezpieczenstwo",
        "sprawdź bezpieczeństwo",
    ],
}

# Add regex patterns for generic word disambiguation
INTENT_PATTERNS_TO_ADD = {
    # "sprawdz" patterns - only trigger with specific context
    "qlty-check": [
        r"sprawdz.*(jakosc|jakość|lint|linting|bledy skladni|błędy składni|formatowanie)",
        r"(zweryfikuj|waliduj).*(kod|format|styl)",
    ],
    "test": [
        r"sprawdz.*(testy|test|unittest|pytest|jest)",
        r"(uruchom|odpal|wykonaj).*(testy|test)",
        r"(czy|co).*(testy|test).*(przeszly|przechodza|failed)",
    ],
    "review": [
        r"sprawdz.*(PR|pull request|merge|zmiany w kodzie|commit)",
        r"(przejrzyj|przegladnij).*(kod|PR|zmiany)",
        r"code review",
    ],
    "security": [
        r"sprawdz.*(bezpieczenstwo|bezpieczeństwo|podatnosci|podatności|injection|xss|sql)",
        r"(audyt|audit).*(security|bezpieczenstwo|bezpieczeństwo)",
    ],
    "fix": [
        r"(napraw|popraw|fix).*(blad|błąd|bug|error|problem)",
        r"(cos|coś).*(nie dziala|nie działa|zepsute|popsute)",
    ],
    "debug": [
        r"(dlaczego|czemu).*(nie dziala|nie działa|crashuje|pada)",
        r"(zbadaj|zdiagnozuj|sprawdz).*(problem|blad|błąd|przyczyne|przyczynę)",
    ],
    "build": [
        r"(zrob|zrób|stworz|stwórz|napisz|zaimplementuj).*(komponent|modul|moduł|feature|funkcje|funkcję)",
        r"(dodaj|utworz|utwórz).*(nowy|nowa|nowe).*(komponent|funkcje|feature)",
    ],
    "refactor": [
        r"(refaktoruj|przebuduj|zrestrukturyzuj|uproscij|uprość).*(kod|funkcje|modul|moduł)",
        r"(wyodrebnij|wydziel).*(do|na).*(funkcj|metod|klas)",
    ],
    "explore": [
        r"(znajdz|znajdź|wyszukaj).*(miejsce|kod|funkcje|plik|gdzie)",
        r"(przeanalizuj|zbadaj).*(strukture|strukturę|architekture|architekturę|codebase)",
    ],
}

def apply_fixes(rules: dict) -> dict:
    skills = rules.get('skills', {})

    # Remove full-phrase keywords
    for skill_name, keywords in KEYWORDS_TO_REMOVE.items():
        if skill_name in skills:
            triggers = skills[skill_name].get('promptTriggers', {})
            current_kw = triggers.get('keywords', [])
            keywords_lower = [k.lower() for k in keywords]
            filtered = [k for k in current_kw if k.lower() not in keywords_lower]
            removed = len(current_kw) - len(filtered)
            if removed > 0:
                print(f"  {skill_name}: Removed {removed} full-phrase keywords")
                triggers['keywords'] = filtered

    # Add intent patterns
    for skill_name, patterns in INTENT_PATTERNS_TO_ADD.items():
        if skill_name in skills:
            triggers = skills[skill_name].get('promptTriggers', {})
            current_patterns = triggers.get('intentPatterns', [])

            added = 0
            for p in patterns:
                if p not in current_patterns:
                    current_patterns.append(p)
                    added += 1

            if added > 0:
                print(f"  {skill_name}: Added {added} intent patterns")
                triggers['intentPatterns'] = current_patterns

    return rules

def main():
    print("Loading v4 rules...")
    rules = load_json(V4_PATH)

    print(f"Found {len(rules.get('skills', {}))} skills")

    print("\nApplying v5 fixes (intentPatterns)...")
    fixed = apply_fixes(rules)

    save_json(fixed, V5_PATH)
    print(f"\nSaved to {V5_PATH}")

if __name__ == "__main__":
    main()
