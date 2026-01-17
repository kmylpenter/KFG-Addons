#!/usr/bin/env python3
"""
Validate keyword matching for skill activation.
Compares which skills WOULD trigger (keyword match) vs which SHOULD trigger (semantic).

This script provides the keyword matching logic. Semantic analysis is done by LLM agents.
"""

import json
import re
from pathlib import Path
from typing import Optional

SKILL_RULES_PATH = Path(__file__).parent / "files" / "skills" / "skill-rules.json"  # Now V5
PROMPTS_PATH = Path(__file__).parent / "extracted-prompts.json"

def load_skill_rules() -> dict:
    """Load skill rules with keywords."""
    with open(SKILL_RULES_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)

def load_prompts() -> list[dict]:
    """Load extracted prompts."""
    with open(PROMPTS_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)

def normalize_text(text: str) -> str:
    """Normalize text for matching."""
    return text.lower().strip()

def check_keyword_match(prompt: str, keywords: list[str]) -> list[str]:
    """Check if any keywords match in the prompt."""
    prompt_lower = normalize_text(prompt)
    matched = []

    for keyword in keywords:
        keyword_lower = normalize_text(keyword)
        # Check for word boundary match (not just substring)
        if keyword_lower in prompt_lower:
            matched.append(keyword)

    return matched

def check_intent_pattern_match(prompt: str, patterns: list[str]) -> list[str]:
    """Check if any intent patterns match."""
    prompt_lower = normalize_text(prompt)
    matched = []

    for pattern in patterns:
        try:
            if re.search(pattern, prompt_lower, re.IGNORECASE):
                matched.append(pattern)
        except re.error:
            continue

    return matched

def find_matching_skills(prompt: str, skill_rules: dict) -> list[dict]:
    """Find all skills that would match the prompt."""
    matches = []

    skills = skill_rules.get('skills', {})

    for skill_name, skill_config in skills.items():
        triggers = skill_config.get('promptTriggers', {})
        keywords = triggers.get('keywords', [])
        patterns = triggers.get('intentPatterns', [])

        keyword_matches = check_keyword_match(prompt, keywords)
        pattern_matches = check_intent_pattern_match(prompt, patterns)

        if keyword_matches or pattern_matches:
            matches.append({
                'skill': skill_name,
                'keyword_matches': keyword_matches,
                'pattern_matches': pattern_matches,
                'priority': skill_config.get('priority', 'medium')
            })

    # Sort by priority
    priority_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
    matches.sort(key=lambda x: priority_order.get(x['priority'], 2))

    return matches

def analyze_prompt(prompt_data: dict, skill_rules: dict) -> dict:
    """Analyze a single prompt for keyword matching."""
    prompt = prompt_data['prompt']

    matches = find_matching_skills(prompt, skill_rules)

    return {
        'prompt': prompt[:200],  # Truncate for readability
        'project': prompt_data.get('project', 'unknown'),
        'matched_skills': [m['skill'] for m in matches],
        'match_details': matches,
        'num_matches': len(matches)
    }

def main():
    """Run keyword analysis on all prompts."""
    skill_rules = load_skill_rules()
    prompts = load_prompts()

    print(f"Loaded {len(prompts)} prompts")
    print(f"Loaded {len(skill_rules.get('skills', {}))} skills")

    results = []
    matched_count = 0
    unmatched_count = 0

    for prompt_data in prompts:
        result = analyze_prompt(prompt_data, skill_rules)
        results.append(result)

        if result['num_matches'] > 0:
            matched_count += 1
        else:
            unmatched_count += 1

    print(f"\n--- Results ---")
    print(f"Matched (at least 1 skill): {matched_count}")
    print(f"Unmatched (no skills): {unmatched_count}")

    # Save results
    output_path = Path(__file__).parent / "keyword-analysis-results.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"\nSaved to {output_path}")

    # Show samples
    print("\n--- Sample MATCHED prompts ---")
    for r in results[:5]:
        if r['num_matches'] > 0:
            print(f"  [{r['matched_skills']}] {r['prompt'][:80]}...")

    print("\n--- Sample UNMATCHED prompts ---")
    unmatched = [r for r in results if r['num_matches'] == 0]
    for r in unmatched[:10]:
        print(f"  {r['prompt'][:100]}...")

if __name__ == "__main__":
    main()
