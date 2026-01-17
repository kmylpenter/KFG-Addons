#!/usr/bin/env python3
"""
Apply Polish translations V3 - with ASCII variants and discovered keywords.
"""

import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ORIGINAL_SKILL_RULES = Path(r"C:\Users\DELL\.claude\skills\skill-rules.json")
POLISH_KEYWORDS_V3 = SCRIPT_DIR / "polish-keywords-v3.json"
OUTPUT_DIR = SCRIPT_DIR / "files" / "skills"
OUTPUT_FILE = OUTPUT_DIR / "skill-rules.json"


def load_json(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(data: dict, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)


def translate_skill_rules(skill_rules: dict, polish_data: dict) -> tuple[dict, dict]:
    skill_keywords = polish_data.get("skills", {})
    agent_keywords = polish_data.get("agents", {})

    stats = {"skills": 0, "agents": 0, "total_keywords": 0}

    # Process skills
    if "skills" in skill_rules:
        for skill_name, skill_data in skill_rules["skills"].items():
            if skill_name in skill_keywords:
                polish_kw = skill_keywords[skill_name]
                if "promptTriggers" in skill_data and "keywords" in skill_data["promptTriggers"]:
                    existing = set(k.lower() for k in skill_data["promptTriggers"]["keywords"])
                    new_polish = [kw for kw in polish_kw if kw.lower() not in existing]
                    skill_data["promptTriggers"]["keywords"].extend(new_polish)
                    print(f"  [SKILL] {skill_name}: +{len(new_polish)} Polish keywords")
                    stats["skills"] += 1
                    stats["total_keywords"] += len(new_polish)

    # Process agents
    if "agents" in skill_rules:
        for agent_name, agent_data in skill_rules["agents"].items():
            if agent_name in agent_keywords:
                polish_kw = agent_keywords[agent_name]
                if "promptTriggers" in agent_data and "keywords" in agent_data["promptTriggers"]:
                    existing = set(k.lower() for k in agent_data["promptTriggers"]["keywords"])
                    new_polish = [kw for kw in polish_kw if kw.lower() not in existing]
                    agent_data["promptTriggers"]["keywords"].extend(new_polish)
                    print(f"  [AGENT] {agent_name}: +{len(new_polish)} Polish keywords")
                    stats["agents"] += 1
                    stats["total_keywords"] += len(new_polish)

    return skill_rules, stats


def main():
    print("=" * 60)
    print("CCv3 Polish Translation V3")
    print("With ASCII variants + discovered keywords")
    print("=" * 60)

    print("\n[1/4] Loading files...")
    skill_rules = load_json(ORIGINAL_SKILL_RULES)
    polish_data = load_json(POLISH_KEYWORDS_V3)

    skill_count = len(skill_rules.get("skills", {}))
    agent_count = len(skill_rules.get("agents", {}))
    print(f"  Original: {skill_count} skills, {agent_count} agents")

    print("\n[2/4] Applying Polish translations...")
    translated, stats = translate_skill_rules(skill_rules, polish_data)

    print("\n[3/4] Validating JSON...")
    try:
        json.loads(json.dumps(translated, ensure_ascii=False))
        print("  [OK] JSON validation passed")
    except Exception as e:
        print(f"  [FAIL] {e}")
        return 1

    print("\n[4/4] Saving...")
    save_json(translated, OUTPUT_FILE)
    print(f"  Saved to: {OUTPUT_FILE}")

    print("\n" + "=" * 60)
    print("Summary:")
    print(f"  Skills translated: {stats['skills']}")
    print(f"  Agents translated: {stats['agents']}")
    print(f"  Total Polish keywords added: {stats['total_keywords']}")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    exit(main())
