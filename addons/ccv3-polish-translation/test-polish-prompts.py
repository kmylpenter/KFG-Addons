#!/usr/bin/env python3
"""
Test Polish skill activation prompts.

This script simulates how skill-rules.json matching works
and tests Polish prompts against expected skill matches.
"""

import json
from pathlib import Path


SKILL_RULES = Path(__file__).parent / "files" / "skills" / "skill-rules.json"


def load_skill_rules():
    with open(SKILL_RULES, "r", encoding="utf-8") as f:
        return json.load(f)


def find_matching_skills(prompt: str, skill_rules: dict) -> list[tuple[str, str]]:
    """Find skills that would match the given prompt."""
    import re
    prompt_lower = prompt.lower()
    matches = []

    # Check skills
    for skill_name, skill_data in skill_rules.get("skills", {}).items():
        triggers = skill_data.get("promptTriggers", {})
        keywords = triggers.get("keywords", [])
        patterns = triggers.get("intentPatterns", [])

        # Check keywords
        for keyword in keywords:
            if keyword.lower() in prompt_lower:
                matches.append(("skill", skill_name, keyword))
                break
        else:
            # Check intent patterns if no keyword matched
            for pattern in patterns:
                try:
                    if re.search(pattern, prompt_lower, re.IGNORECASE):
                        matches.append(("skill", skill_name, f"pattern:{pattern[:30]}"))
                        break
                except re.error:
                    continue

    # Check agents
    for agent_name, agent_data in skill_rules.get("agents", {}).items():
        triggers = agent_data.get("promptTriggers", {})
        keywords = triggers.get("keywords", [])
        patterns = triggers.get("intentPatterns", [])

        # Check keywords
        for keyword in keywords:
            if keyword.lower() in prompt_lower:
                matches.append(("agent", agent_name, keyword))
                break
        else:
            # Check intent patterns if no keyword matched
            for pattern in patterns:
                try:
                    if re.search(pattern, prompt_lower, re.IGNORECASE):
                        matches.append(("agent", agent_name, f"pattern:{pattern[:30]}"))
                        break
                except re.error:
                    continue

    return matches


def main():
    print("=" * 70)
    print("CCv3 Polish Translation - Test Suite")
    print("=" * 70)

    skill_rules = load_skill_rules()

    # Test cases: (Polish prompt, expected matches)
    test_cases = [
        # Skills
        ("napraw tego buga", ["fix"]),
        ("zbuduj nową funkcjonalność", ["build"]),
        ("eksploruj bazę kodu", ["explore"]),
        ("debuguj problem z autentykacją", ["debug"]),
        ("stwórz handoff przed wyjściem", ["create_handoff"]),
        ("wznów handoff z wczoraj", ["resume_handoff"]),
        ("commituj zmiany", ["commit"]),
        ("przejrzyj mój kod", ["review"]),
        ("sprawdź bezpieczeństwo", ["security"]),
        ("uruchom wszystkie testy", ["test"]),
        ("refaktoruj ten moduł", ["refactor"]),
        ("migruj do nowej wersji", ["migrate"]),
        ("przygotuj release", ["release"]),
        ("szukaj w kodzie", ["morph-search"]),
        ("sprawdź jakość kodu", ["qlty-check"]),
        ("analizuj sesję", ["braintrust-analyze"]),
        ("zapamiętaj to", ["remember"]),
        ("przypomnij learningi", ["recall"]),
        ("martwy kod w projekcie", ["dead-code"]),
        ("co może pójść źle", ["premortem"]),

        # Agents
        ("eksploruj kod projektu", ["scout"]),
        ("zbadaj najlepsze praktyki", ["oracle"]),
        ("stwórz plan implementacji", ["plan-agent"]),
        ("waliduj plan przed implementacją", ["validate-agent"]),
        ("debuguj błąd w logach", ["debug-agent"]),
        ("analizuj strukturę repo", ["pathfinder"]),

        # Math
        ("rozwiąż równanie", ["math-unified"]),
        ("przelicz jednostki", ["pint-compute"]),
        ("pole wielokąta", ["shapely-compute"]),

        # Edge cases - should NOT trigger generic skills
        ("w projekcie jest błąd", []),  # "w" alone should not trigger
        ("z tego kodu", []),  # "z" alone should not trigger

        # ASCII variants (without Polish diacritics)
        ("sprawdz bezpieczenstwo", ["security"]),  # sprawdź → sprawdz
        ("napraw blad", ["fix"]),  # błąd → blad
        ("zrob commit", ["commit"]),  # zrób → zrob
        ("wznow handoff", ["resume_handoff"]),  # wznów → wznow
    ]

    passed = 0
    failed = 0

    print("\nRunning tests...\n")

    for prompt, expected in test_cases:
        matches = find_matching_skills(prompt, skill_rules)
        matched_names = [m[1] for m in matches]

        # Check if expected skills are in matches
        all_expected_found = all(exp in matched_names for exp in expected)
        no_unexpected = len(expected) == 0 and len(matches) == 0 or len(expected) > 0

        if all_expected_found and (len(expected) == 0 or len(matches) > 0):
            print(f"  [PASS] \"{prompt}\"")
            print(f"         Expected: {expected}, Got: {matched_names}")
            passed += 1
        else:
            print(f"  [FAIL] \"{prompt}\"")
            print(f"         Expected: {expected}, Got: {matched_names}")
            failed += 1

    print("\n" + "=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    exit(main())
