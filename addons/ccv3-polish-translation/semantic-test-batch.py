#!/usr/bin/env python3
"""
Batch semantic analysis helper.
Prepares prompts for LLM agent analysis.

Usage: python semantic-test-batch.py <batch_start> <batch_size>
"""

import json
import sys
from pathlib import Path

PROMPTS_PATH = Path(__file__).parent / "extracted-prompts.json"
KEYWORD_RESULTS_PATH = Path(__file__).parent / "keyword-analysis-results.json"

# Skills that agents can recommend
AVAILABLE_SKILLS = [
    "compound-learnings", "mot", "debug-hooks", "hook-developer", "implement_plan",
    "plan-agent", "skill-developer", "slash-commands", "sub-agents", "commit",
    "describe_pr", "review", "fix", "refactor", "test", "tdd", "security",
    "release", "build", "explore", "research", "research-external", "onboard",
    "debug", "premortem", "migrate", "create_handoff", "resume_handoff",
    "help", "continuity_ledger", "recall-reasoning", "math-router", "math-unified"
]

def load_data():
    with open(PROMPTS_PATH, 'r', encoding='utf-8') as f:
        prompts = json.load(f)
    with open(KEYWORD_RESULTS_PATH, 'r', encoding='utf-8') as f:
        keyword_results = json.load(f)
    return prompts, keyword_results

def prepare_batch(start: int, size: int) -> list[dict]:
    """Prepare a batch of prompts for analysis."""
    prompts, keyword_results = load_data()

    batch = []
    for i in range(start, min(start + size, len(prompts))):
        prompt = prompts[i]
        kw_result = keyword_results[i] if i < len(keyword_results) else {}

        batch.append({
            'id': i,
            'prompt': prompt['prompt'][:500],  # Limit length
            'keyword_matched_skills': kw_result.get('matched_skills', []),
            'num_keyword_matches': kw_result.get('num_matches', 0)
        })

    return batch

def main():
    if len(sys.argv) < 3:
        print("Usage: python semantic-test-batch.py <batch_start> <batch_size>")
        print("\nExample: python semantic-test-batch.py 0 50")
        sys.exit(1)

    start = int(sys.argv[1])
    size = int(sys.argv[2])

    batch = prepare_batch(start, size)

    print(f"Batch {start}-{start+size}: {len(batch)} prompts")
    print(f"\nAvailable skills for recommendation:\n{', '.join(AVAILABLE_SKILLS)}")
    print(f"\n{'='*80}")

    for item in batch:
        print(f"\n--- Prompt #{item['id']} ---")
        print(f"Text: {item['prompt']}")
        print(f"Keyword matched: {item['keyword_matched_skills']}")
        print(f"Num matches: {item['num_keyword_matches']}")

if __name__ == "__main__":
    main()
