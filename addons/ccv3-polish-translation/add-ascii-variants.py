#!/usr/bin/env python3
"""
Add ASCII variants of Polish keywords.

For each Polish word with diacritics (ąćęłńóśźż),
adds a version without diacritics (acelnoszz).
"""

import json
from pathlib import Path

# Diacritic mapping
POLISH_TO_ASCII = str.maketrans({
    'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
    'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
    'Ą': 'A', 'Ć': 'C', 'Ę': 'E', 'Ł': 'L', 'Ń': 'N',
    'Ó': 'O', 'Ś': 'S', 'Ź': 'Z', 'Ż': 'Z'
})


def to_ascii(text: str) -> str:
    """Convert Polish diacritics to ASCII."""
    return text.translate(POLISH_TO_ASCII)


def has_polish_chars(text: str) -> bool:
    """Check if text has Polish diacritics."""
    return any(c in text for c in 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ')


def add_ascii_variants(keywords: list[str]) -> list[str]:
    """Add ASCII variant for each keyword with Polish chars."""
    result = list(keywords)  # Keep originals

    for kw in keywords:
        if has_polish_chars(kw):
            ascii_variant = to_ascii(kw)
            if ascii_variant not in result:
                result.append(ascii_variant)

    return result


def process_keywords_file(input_path: Path, output_path: Path):
    """Process polish-keywords-v2.json and add ASCII variants."""
    print("=" * 60)
    print("Adding ASCII Variants to Polish Keywords")
    print("=" * 60)

    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    original_count = 0
    added_count = 0

    # Process skills
    for skill_name, keywords in data.get("skills", {}).items():
        original = len(keywords)
        data["skills"][skill_name] = add_ascii_variants(keywords)
        added = len(data["skills"][skill_name]) - original
        original_count += original
        added_count += added
        if added > 0:
            print(f"  [SKILL] {skill_name}: +{added} ASCII variants")

    # Process agents
    for agent_name, keywords in data.get("agents", {}).items():
        original = len(keywords)
        data["agents"][agent_name] = add_ascii_variants(keywords)
        added = len(data["agents"][agent_name]) - original
        original_count += original
        added_count += added
        if added > 0:
            print(f"  [AGENT] {agent_name}: +{added} ASCII variants")

    # Update version
    data["version"] = "3.0"
    data["note"] = "Includes ASCII variants for all Polish words with diacritics"

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"\n[DONE] Original keywords: {original_count}")
    print(f"[DONE] ASCII variants added: {added_count}")
    print(f"[DONE] Total keywords now: {original_count + added_count}")
    print(f"[SAVED] {output_path}")


def main():
    script_dir = Path(__file__).parent
    # Use enriched version with discovered keywords
    input_path = script_dir / "polish-keywords-v2-enriched.json"
    output_path = script_dir / "polish-keywords-v3.json"

    process_keywords_file(input_path, output_path)


if __name__ == "__main__":
    main()
