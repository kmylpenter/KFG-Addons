#!/usr/bin/env python3
"""
Add discovered keywords from user prompt analysis to polish-keywords-v2.json
"""

import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent

# Keywords discovered from actual usage (5934 prompts analyzed)
# These are the most frequently used Polish words in commands
DISCOVERED_KEYWORDS = {
    # High frequency imperatives (>40 uses)
    "general_commands": [
        "dodaj", "zaktualizuj", "kontynuuj", "zweryfikuj", "pamietaj",
        "dzialaj", "zapoznaj", "sprobuj", "wykonaj", "oddeleguj",
        "upewnij", "uzyj", "zaimplementuj", "dostosuj", "przygotuj",
        "przetestuj", "przeanalizuj", "wygeneruj", "przejrzyj",
        "zaproponuj", "czekaj", "implementuj", "rozpocznij", "zainstaluj",
        "zacznij", "skonfiguruj", "zaczynaj", "wyszukaj", "przeczytaj",
        "podaj", "generuj"
    ],

    # With diacritics versions (from top_polish_words)
    "with_diacritics": [
        "błąd", "działa", "usuń", "sprawdź", "spróbuj", "zrób",
        "naprawić", "sprawdzić", "żeby", "możemy", "będzie",
        "więcej", "zmienić", "przetestować", "usunąć"
    ],

    # Error/problem related
    "errors": [
        "blad", "bledy", "problem", "problemy", "error", "errors",
        "popraw", "poprawic", "napraw", "naprawic"
    ],

    # File/code related
    "files_code": [
        "plik", "pliku", "pliki", "plikow", "plikach",
        "kod", "kodu", "kodzie", "funkcja", "klasa"
    ],

    # Project related
    "projects": [
        "projekt", "projektu", "projekty", "projektow",
        "repo", "branch", "commit", "push"
    ],

    # Actions discovered
    "actions": [
        "uruchom", "zatrzymaj", "wyswietl", "pokaz", "zapisz",
        "wczytaj", "zaladuj", "eksportuj", "importuj"
    ]
}

# Map discovered keywords to specific skills
SKILL_KEYWORD_MAP = {
    "fix": ["napraw", "naprawic", "popraw", "poprawic", "blad", "bledy", "bledy", "problem", "problemy"],
    "debug": ["problem", "problemy", "blad", "bledy", "dlaczego", "czemu"],
    "build": ["zbuduj", "stworz", "dodaj", "zaimplementuj", "implementuj"],
    "explore": ["zapoznaj", "przeanalizuj", "przejrzyj", "zbadaj"],
    "test": ["przetestuj", "uruchom", "sprawdz", "zweryfikuj"],
    "commit": ["commituj", "zacommituj", "zatwierdz", "zapisz"],
    "review": ["przejrzyj", "sprawdz", "zweryfikuj", "oceń"],
    "refactor": ["refaktoruj", "przebuduj", "popraw", "uporzadkuj"],
    "implement_plan": ["wykonaj", "zrealizuj", "wdroz", "zaimplementuj"],
    "create_handoff": ["zakoncz", "podsumuj", "przekaz", "handoff"],
    "resume_handoff": ["wznow", "kontynuuj", "odbierz", "gdzie skonczylem"],
    "workflow-router": ["zacznij", "rozpocznij", "od czego", "jak zaczac", "pomoz"],
    "recall": ["przypomnij", "pamietaj", "co wczesniej", "poprzednio"],
    "remember": ["zapamietaj", "zapisz", "pamietaj"],
    "onboard": ["zapoznaj", "poznaj", "nowy projekt", "pierwszy raz"],
    "morph-search": ["szukaj", "wyszukaj", "znajdz", "grep"],
    "qlty-check": ["sprawdz", "zweryfikuj", "lint", "jakosc"],
    "migrate": ["migruj", "przenies", "zaktualizuj", "upgrade"],
    "security": ["bezpieczenstwo", "sprawdz", "podatnosc", "security"],
    "tdd": ["testy", "testuj", "najpierw test", "tdd"],
    "dead-code": ["martwy kod", "nieuzywane", "usun", "cleanup"]
}


def load_json(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(data: dict, path: Path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main():
    print("=" * 60)
    print("Adding Discovered Keywords to polish-keywords-v2.json")
    print("=" * 60)

    input_path = SCRIPT_DIR / "polish-keywords-v2.json"
    output_path = SCRIPT_DIR / "polish-keywords-v2-enriched.json"

    data = load_json(input_path)
    added_total = 0

    for skill_name, new_keywords in SKILL_KEYWORD_MAP.items():
        if skill_name in data.get("skills", {}):
            existing = set(k.lower() for k in data["skills"][skill_name])
            to_add = [kw for kw in new_keywords if kw.lower() not in existing]
            if to_add:
                data["skills"][skill_name].extend(to_add)
                print(f"  [SKILL] {skill_name}: +{len(to_add)} keywords")
                added_total += len(to_add)

    # Update metadata
    data["version"] = "2.1"
    data["note"] = "Enriched with keywords from 5934 user prompts analysis"

    save_json(data, output_path)

    print(f"\n[DONE] Added {added_total} discovered keywords")
    print(f"[SAVED] {output_path}")


if __name__ == "__main__":
    main()
