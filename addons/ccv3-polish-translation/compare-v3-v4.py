#!/usr/bin/env python3
"""
Compare keyword matching results between v3 and v4 skill-rules.
"""

import json
import re
from pathlib import Path

V3_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules.json"
V4_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules-v5.json"
PROMPTS_PATH = Path(__file__).parent / "extracted-prompts.json"

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def check_keyword_match(prompt: str, keywords: list[str]) -> list[str]:
    prompt_lower = prompt.lower().strip()
    matched = []
    for keyword in keywords:
        if keyword.lower() in prompt_lower:
            matched.append(keyword)
    return matched

def check_pattern_match(prompt: str, patterns: list[str]) -> list[str]:
    prompt_lower = prompt.lower().strip()
    matched = []
    for pattern in patterns:
        try:
            if re.search(pattern, prompt_lower, re.IGNORECASE):
                matched.append(pattern)
        except:
            continue
    return matched

def find_matching_skills(prompt: str, rules: dict) -> set[str]:
    matches = set()
    for skill_name, skill_config in rules.get('skills', {}).items():
        triggers = skill_config.get('promptTriggers', {})
        keywords = triggers.get('keywords', [])
        patterns = triggers.get('intentPatterns', [])

        if check_keyword_match(prompt, keywords) or check_pattern_match(prompt, patterns):
            matches.add(skill_name)
    return matches

def main():
    v3_rules = load_json(V3_PATH)
    v4_rules = load_json(V4_PATH)
    prompts = load_json(PROMPTS_PATH)

    print(f"Comparing {len(prompts)} prompts...")
    print("=" * 60)

    v3_total_matches = 0
    v4_total_matches = 0

    v3_excessive = 0  # prompts with 5+ matches
    v4_excessive = 0

    improvements = []
    regressions = []

    for i, p in enumerate(prompts):
        prompt = p['prompt']

        v3_matches = find_matching_skills(prompt, v3_rules)
        v4_matches = find_matching_skills(prompt, v4_rules)

        v3_total_matches += len(v3_matches)
        v4_total_matches += len(v4_matches)

        if len(v3_matches) >= 5:
            v3_excessive += 1
        if len(v4_matches) >= 5:
            v4_excessive += 1

        # Check for improvements (v4 matches fewer skills = less false positives)
        if len(v4_matches) < len(v3_matches):
            removed = v3_matches - v4_matches
            improvements.append({
                'id': i,
                'prompt': prompt[:80],
                'v3_count': len(v3_matches),
                'v4_count': len(v4_matches),
                'removed': removed
            })

        # Check for regressions (v4 matches more skills)
        elif len(v4_matches) > len(v3_matches):
            added = v4_matches - v3_matches
            regressions.append({
                'id': i,
                'prompt': prompt[:80],
                'v3_count': len(v3_matches),
                'v4_count': len(v4_matches),
                'added': added
            })

    print(f"\n=== SUMMARY ===")
    print(f"  V3 total skill matches: {v3_total_matches}")
    print(f"  V4 total skill matches: {v4_total_matches}")
    print(f"  Reduction: {v3_total_matches - v4_total_matches} ({(1 - v4_total_matches/v3_total_matches)*100:.1f}%)")

    print(f"\n  V3 prompts with 5+ matches: {v3_excessive}")
    print(f"  V4 prompts with 5+ matches: {v4_excessive}")

    print(f"\n+++ IMPROVEMENTS (V4 fewer false positives): {len(improvements)}")
    for imp in improvements[:10]:
        print(f"  #{imp['id']}: {imp['v3_count']} -> {imp['v4_count']} (removed: {imp['removed']})")

    if len(improvements) > 10:
        print(f"  ... and {len(improvements) - 10} more")

    print(f"\n--- REGRESSIONS (V4 more matches): {len(regressions)}")
    for reg in regressions[:10]:
        print(f"  #{reg['id']}: {reg['v3_count']} -> {reg['v4_count']} (added: {reg['added']})")

    if len(regressions) > 10:
        print(f"  ... and {len(regressions) - 10} more")

    # Check specifically for "PR", "nia", "ast" false positives
    print("\n*** SPECIFIC FIXES CHECK ***")

    pr_v3 = sum(1 for p in prompts if 'github-search' in find_matching_skills(p['prompt'], v3_rules))
    pr_v4 = sum(1 for p in prompts if 'github-search' in find_matching_skills(p['prompt'], v4_rules))
    print(f"  github-search matches: V3={pr_v3} -> V4={pr_v4}")

    nia_v3 = sum(1 for p in prompts if 'nia-docs' in find_matching_skills(p['prompt'], v3_rules))
    nia_v4 = sum(1 for p in prompts if 'nia-docs' in find_matching_skills(p['prompt'], v4_rules))
    print(f"  nia-docs matches: V3={nia_v3} -> V4={nia_v4}")

    ast_v3 = sum(1 for p in prompts if 'ast-grep-find' in find_matching_skills(p['prompt'], v3_rules))
    ast_v4 = sum(1 for p in prompts if 'ast-grep-find' in find_matching_skills(p['prompt'], v4_rules))
    print(f"  ast-grep-find matches: V3={ast_v3} -> V4={ast_v4}")

if __name__ == "__main__":
    main()
