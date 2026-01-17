#!/usr/bin/env python3
"""
Apply Polish translations to skill-rules.json

This script:
1. Reads the original skill-rules.json
2. Reads polish-keywords.json mapping
3. Adds Polish keywords to each skill/agent
4. Validates the resulting JSON
5. Writes the translated version
"""

import json
import re
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).parent
ORIGINAL_SKILL_RULES = Path(r"C:\Users\DELL\.claude\skills\skill-rules.json")
POLISH_KEYWORDS = SCRIPT_DIR / "polish-keywords.json"
OUTPUT_DIR = SCRIPT_DIR / "files" / "skills"
OUTPUT_FILE = OUTPUT_DIR / "skill-rules.json"


def load_json(path: Path) -> dict:
    """Load JSON file with UTF-8 encoding."""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(data: dict, path: Path) -> None:
    """Save JSON file with UTF-8 encoding and nice formatting."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)


def find_matching_polish_keywords(english_keywords: list[str], mapping: dict) -> list[str]:
    """Find Polish equivalents for English keywords."""
    polish_keywords = []

    for eng_keyword in english_keywords:
        eng_lower = eng_keyword.lower()

        # Check each mapping entry
        for eng_word, polish_forms in mapping.items():
            # Direct match or word is part of keyword
            if eng_word in eng_lower or eng_lower in eng_word:
                polish_keywords.extend(polish_forms)
            # Check if any Polish form might already be there (avoid duplicates)
            elif any(pf.lower() in eng_lower for pf in polish_forms[:2]):
                continue

    # Remove duplicates while preserving order
    seen = set()
    unique_polish = []
    for kw in polish_keywords:
        kw_lower = kw.lower()
        if kw_lower not in seen:
            seen.add(kw_lower)
            unique_polish.append(kw)

    return unique_polish


def add_skill_specific_keywords(skill_name: str, skill_specific: dict) -> list[str]:
    """Get skill-specific Polish keywords."""
    return skill_specific.get(skill_name, [])


def translate_skill_rules(skill_rules: dict, polish_mapping: dict) -> dict:
    """Add Polish keywords to all skills and agents."""
    general_mapping = polish_mapping.get("mapping", {})
    skill_specific = polish_mapping.get("skill_specific", {})
    agents_specific = polish_mapping.get("agents_specific", {})

    # Process skills
    if "skills" in skill_rules:
        for skill_name, skill_data in skill_rules["skills"].items():
            if "promptTriggers" in skill_data and "keywords" in skill_data["promptTriggers"]:
                original_keywords = skill_data["promptTriggers"]["keywords"]

                # Find matching Polish keywords
                polish_kw = find_matching_polish_keywords(original_keywords, general_mapping)

                # Add skill-specific Polish keywords
                polish_kw.extend(add_skill_specific_keywords(skill_name, skill_specific))

                # Remove duplicates and add to original
                existing = set(k.lower() for k in original_keywords)
                new_polish = [kw for kw in polish_kw if kw.lower() not in existing]

                # Append Polish keywords
                skill_data["promptTriggers"]["keywords"].extend(new_polish)

                print(f"  [SKILL] {skill_name}: +{len(new_polish)} Polish keywords")

    # Process agents
    if "agents" in skill_rules:
        for agent_name, agent_data in skill_rules["agents"].items():
            if "promptTriggers" in agent_data and "keywords" in agent_data["promptTriggers"]:
                original_keywords = agent_data["promptTriggers"]["keywords"]

                # Find matching Polish keywords
                polish_kw = find_matching_polish_keywords(original_keywords, general_mapping)

                # Add agent-specific Polish keywords
                polish_kw.extend(agents_specific.get(agent_name, []))

                # Remove duplicates and add to original
                existing = set(k.lower() for k in original_keywords)
                new_polish = [kw for kw in polish_kw if kw.lower() not in existing]

                # Append Polish keywords
                agent_data["promptTriggers"]["keywords"].extend(new_polish)

                print(f"  [AGENT] {agent_name}: +{len(new_polish)} Polish keywords")

    return skill_rules


def validate_json(data: dict) -> bool:
    """Validate that the JSON structure is correct."""
    try:
        # Try to serialize and deserialize
        json_str = json.dumps(data, ensure_ascii=False)
        json.loads(json_str)

        # Check structure
        assert "skills" in data, "Missing 'skills' key"
        assert "agents" in data, "Missing 'agents' key"

        # Check each skill has required structure
        for skill_name, skill_data in data["skills"].items():
            assert "promptTriggers" in skill_data, f"Skill {skill_name} missing promptTriggers"
            assert "keywords" in skill_data["promptTriggers"], f"Skill {skill_name} missing keywords"

        return True
    except Exception as e:
        print(f"Validation error: {e}")
        return False


def main():
    print("=" * 60)
    print("CCv3 Polish Translation - Apply Translations")
    print("=" * 60)

    # Load files
    print("\n[1/4] Loading files...")
    skill_rules = load_json(ORIGINAL_SKILL_RULES)
    polish_mapping = load_json(POLISH_KEYWORDS)

    skill_count = len(skill_rules.get("skills", {}))
    agent_count = len(skill_rules.get("agents", {}))
    print(f"  Loaded {skill_count} skills and {agent_count} agents")

    # Apply translations
    print("\n[2/4] Applying Polish translations...")
    translated = translate_skill_rules(skill_rules, polish_mapping)

    # Validate
    print("\n[3/4] Validating JSON...")
    if validate_json(translated):
        print("  [OK] JSON validation passed")
    else:
        print("  [FAIL] JSON validation FAILED - aborting")
        return 1

    # Save
    print("\n[4/4] Saving translated skill-rules.json...")
    save_json(translated, OUTPUT_FILE)
    print(f"  Saved to: {OUTPUT_FILE}")

    print("\n" + "=" * 60)
    print("Translation complete!")
    print(f"Total skills processed: {skill_count}")
    print(f"Total agents processed: {agent_count}")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    exit(main())
