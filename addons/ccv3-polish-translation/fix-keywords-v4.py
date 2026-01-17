#!/usr/bin/env python3
"""
Fix keyword issues discovered in semantic validation testing.

Issues found:
1. Substring false positives: "PR", "nia", "ast" match within Polish words
2. "sprawdz" too generic - triggers 4-5 skills
3. Missing Polish keywords: refaktoring, zrób, stwórz, dokończ, schrznilo
4. Session continuation summaries trigger too many skills

This script modifies skill-rules.json to fix these issues.
"""

import json
import re
from pathlib import Path

SKILL_RULES_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules.json"
OUTPUT_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules-v4.json"

def load_skill_rules() -> dict:
    with open(SKILL_RULES_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_skill_rules(rules: dict, path: Path):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(rules, f, indent=4, ensure_ascii=False)
    print(f"Saved to {path}")

# Keywords to REMOVE (too generic, cause false positives)
KEYWORDS_TO_REMOVE = {
    # "PR" is too short, matches Polish words like PRojekty, PRzeczytaj
    "github-search": ["PR"],

    # "nia" matches Polish words ending in -nia (ustawienia, roznica)
    "nia-docs": ["nia"],

    # "ast" matches Polish words (zastanow, pastelowe)
    "ast-grep-find": ["ast"],

    # These are too generic without action context
    "migrate": ["zaktualizuj", "zaktualizować", "przenies", "przeniesc", "przenies", "przeniesc"],

    # "sprawdz" alone triggers too many skills - keep only with specific context
    "qlty-check": ["sprawdz", "sprawdź"],
    "security": ["sprawdz", "sprawdź"],

    # Standalone generic words
    "test": ["sprawdz", "sprawdź"],
    "review": ["sprawdz", "sprawdź"],
}

# Keywords to ADD (discovered as missing)
KEYWORDS_TO_ADD = {
    "refactor": [
        "refaktoring",
        "refaktoruj",
        "refaktoryzacja",
        "refaktoryzuj",
        "uprość kod",
        "uproscic kod",
        "zrestrukturyzuj",
        "przebuduj kod",
    ],

    "build": [
        "stwórz",
        "stworz",
        "zbuduj",
        "zrób feature",
        "zrob feature",
        "dokończ",
        "dokoncz",
        "rozszerz",
        "rozbuduj",
        "zaimplementuj",
        "napisz nowy",
        "dodaj nowy",
        "utwórz nowy",
        "utworz nowy",
    ],

    "fix": [
        "fix",  # standalone English word
        "napraw to",
        "schrznilo",
        "popsulo",
        "zepsulo",
        "nie dziala prawidlowo",
        "nie działa prawidłowo",
        "przestalo dzialac",
        "przestało działać",
        "SyntaxError",
        "TypeError",
        "Error:",
        "Exception:",
        "Failed to",
        "Cannot find",
        "blad kompilacji",
        "błąd kompilacji",
    ],

    "debug": [
        "dlaczego nie dziala",
        "dlaczego nie działa",
        "co powoduje",
        "co jest przyczyna",
        "co jest przyczyną",
        "zbadaj problem",
        "zdiagnozuj",
        "stracilismy",
        "straciliśmy",
        "zniknelo",
        "zniknęło",
    ],

    "help": [
        "jak pracowac z claude",
        "jak pracować z claude",
        "jak używać",
        "jak uzywac",
        "co robi komenda",
        "opis komend",
        "jakie mam opcje",
    ],

    "explore": [
        "znajdz miejsce",
        "znajdź miejsce",
        "gdzie jest kod",
        "wyszukaj w plikach",
        "przeanalizuj strukture",
        "przeanalizuj strukturę",
    ],

    # More specific patterns for sprawdz
    "qlty-check": [
        "sprawdz jakosc kodu",
        "sprawdź jakość kodu",
        "sprawdz linting",
        "uruchom linter",
    ],

    "test": [
        "sprawdz testy",
        "sprawdź testy",
        "uruchom testy",
        "odpal testy",
        "pytest",
        "npm test",
        "do testow",
        "do testów",
    ],

    "review": [
        "sprawdz PR",
        "sprawdź PR",
        "przejrzyj kod",
        "code review",
        "sprawdz zmiany w PR",
    ],

    "security": [
        "sprawdz bezpieczenstwo",
        "sprawdź bezpieczeństwo",
        "audyt bezpieczenstwa",
        "audyt bezpieczeństwa",
        "znajdz luki",
        "znajdź luki",
    ],
}

# Intent patterns to ADD
PATTERNS_TO_ADD = {
    "fix": [
        r"(SyntaxError|TypeError|ReferenceError|Error:)",
        r"(Failed to|Cannot|Unable to).*",
        r"(nie dziala|nie działa).*(prawidlowo|prawidłowo|poprawnie)",
        r"(przestalo|przestało).*dzialac",
    ],

    "debug": [
        r"(dlaczego|czemu).*(nie dziala|nie działa|nie wykrywa)",
        r"(co powoduje|co jest przyczyna)",
    ],

    "build": [
        r"(stwórz|stworz|zbuduj|napisz).*?(komponent|moduł|funkcję|feature)",
        r"(dodaj|utwórz|utworz).*?(nowy|nowa|nowe)",
    ],
}

def apply_fixes(rules: dict) -> dict:
    """Apply all keyword fixes to skill rules."""
    skills = rules.get('skills', {})

    # Remove problematic keywords
    for skill_name, keywords_to_remove in KEYWORDS_TO_REMOVE.items():
        if skill_name in skills:
            triggers = skills[skill_name].get('promptTriggers', {})
            current_keywords = triggers.get('keywords', [])

            # Filter out the problematic keywords
            filtered = [k for k in current_keywords if k.lower() not in [kr.lower() for kr in keywords_to_remove]]

            removed_count = len(current_keywords) - len(filtered)
            if removed_count > 0:
                print(f"  {skill_name}: Removed {removed_count} keywords: {keywords_to_remove}")
                triggers['keywords'] = filtered

    # Add missing keywords
    for skill_name, keywords_to_add in KEYWORDS_TO_ADD.items():
        if skill_name in skills:
            triggers = skills[skill_name].get('promptTriggers', {})
            current_keywords = triggers.get('keywords', [])

            # Add new keywords (avoid duplicates)
            current_lower = [k.lower() for k in current_keywords]
            added = []
            for kw in keywords_to_add:
                if kw.lower() not in current_lower:
                    current_keywords.append(kw)
                    added.append(kw)

            if added:
                print(f"  {skill_name}: Added {len(added)} keywords")
                triggers['keywords'] = current_keywords

    # Add intent patterns
    for skill_name, patterns in PATTERNS_TO_ADD.items():
        if skill_name in skills:
            triggers = skills[skill_name].get('promptTriggers', {})
            current_patterns = triggers.get('intentPatterns', [])

            added = []
            for pattern in patterns:
                if pattern not in current_patterns:
                    current_patterns.append(pattern)
                    added.append(pattern)

            if added:
                print(f"  {skill_name}: Added {len(added)} intent patterns")
                triggers['intentPatterns'] = current_patterns

    return rules

def main():
    print("Loading skill-rules.json...")
    rules = load_skill_rules()

    print(f"Found {len(rules.get('skills', {}))} skills")

    print("\nApplying fixes...")
    fixed_rules = apply_fixes(rules)

    # Save to v4 file
    save_skill_rules(fixed_rules, OUTPUT_PATH)

    print("\nDone! Review the changes and copy to final location if satisfied.")

if __name__ == "__main__":
    main()
