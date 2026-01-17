#!/usr/bin/env python3
"""
Extract user prompts from Claude Code conversation history for keyword testing.
Collects prompts from all projects in ~/.claude/projects/
"""

import json
import os
import random
from pathlib import Path
from typing import Generator

PROJECTS_DIR = Path(r"C:\Users\DELL\.claude\projects")
OUTPUT_FILE = Path(__file__).parent / "extracted-prompts.json"

def extract_prompts_from_jsonl(jsonl_path: Path) -> Generator[dict, None, None]:
    """Extract user prompts from a .jsonl session file."""
    try:
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            for line in f:
                try:
                    entry = json.loads(line.strip())
                    if entry.get('type') == 'user' and 'message' in entry:
                        content = entry['message'].get('content', '')
                        # Skip empty or very short prompts
                        if isinstance(content, str) and len(content) > 5:
                            # Skip command-only prompts (pure /slash commands)
                            if content.startswith('<command-message>') and '</command-args>' in content:
                                # Extract just the args part if it exists
                                if '<command-args>' in content:
                                    args_start = content.find('<command-args>') + len('<command-args>')
                                    args_end = content.find('</command-args>')
                                    args = content[args_start:args_end].strip()
                                    if args and len(args) > 5:
                                        yield {
                                            'prompt': args,
                                            'session': jsonl_path.stem,
                                            'project': jsonl_path.parent.name
                                        }
                            else:
                                yield {
                                    'prompt': content,
                                    'session': jsonl_path.stem,
                                    'project': jsonl_path.parent.name
                                }
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        print(f"Error reading {jsonl_path}: {e}")

def collect_all_prompts() -> list[dict]:
    """Collect prompts from all projects."""
    all_prompts = []

    # Find all .jsonl files in projects folder
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue

        for jsonl_file in project_dir.glob("*.jsonl"):
            for prompt in extract_prompts_from_jsonl(jsonl_file):
                all_prompts.append(prompt)

    return all_prompts

def filter_meaningful_prompts(prompts: list[dict]) -> list[dict]:
    """Filter out trivial prompts."""
    meaningful = []
    seen = set()

    for p in prompts:
        text = p['prompt']

        # Skip duplicates
        if text in seen:
            continue
        seen.add(text)

        # Skip very short
        if len(text) < 10:
            continue

        # Skip pure numbers or single words
        if text.strip().isdigit():
            continue
        if len(text.split()) < 2:
            continue

        # Skip system/hook messages
        if '<system-reminder>' in text:
            continue
        if 'hook success' in text.lower():
            continue

        meaningful.append(p)

    return meaningful

def main():
    print("Extracting prompts from conversation history...")

    all_prompts = collect_all_prompts()
    print(f"Found {len(all_prompts)} total prompts")

    meaningful = filter_meaningful_prompts(all_prompts)
    print(f"Filtered to {len(meaningful)} meaningful prompts")

    # Randomly select 300 prompts
    if len(meaningful) > 300:
        selected = random.sample(meaningful, 300)
    else:
        selected = meaningful

    print(f"Selected {len(selected)} prompts for testing")

    # Save to file
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(selected, f, indent=2, ensure_ascii=False)

    print(f"Saved to {OUTPUT_FILE}")

    # Print sample
    print("\n--- Sample prompts ---")
    for p in selected[:5]:
        print(f"  [{p['project'][:30]}] {p['prompt'][:80]}...")

if __name__ == "__main__":
    main()
