#!/usr/bin/env python3
"""
Analyze user prompts from conversation history to extract Polish keywords.

This script:
1. Scans all .jsonl files in ~/.claude/projects/
2. Extracts user messages
3. Identifies Polish words and patterns
4. Outputs frequency analysis of Polish keywords
"""

import json
import re
import os
from pathlib import Path
from collections import Counter
from typing import Generator
import unicodedata

# Polish-specific characters
POLISH_CHARS = set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")

# Common Polish stopwords to exclude
POLISH_STOPWORDS = {
    "i", "w", "z", "na", "do", "to", "nie", "się", "że", "o", "a", "ale",
    "jak", "co", "po", "za", "od", "tak", "jest", "są", "być", "był",
    "tylko", "też", "już", "jeszcze", "może", "można", "bardzo", "tu",
    "tam", "kiedy", "gdzie", "który", "która", "które", "ten", "ta", "te",
    "tego", "tej", "tych", "tym", "mnie", "mi", "ja", "ty", "on", "ona",
    "my", "wy", "oni", "one", "dla", "przy", "przez", "ze", "we", "nad",
    "pod", "przed", "bo", "by", "czy", "gdy", "gdyby", "więc", "lub",
    "albo", "ani", "jeśli", "jeżeli", "choć", "chociaż", "czyli", "oraz"
}

# Min word length to consider
MIN_WORD_LENGTH = 3


def is_polish_word(word: str) -> bool:
    """Check if word likely contains Polish-specific characters."""
    return any(c in POLISH_CHARS for c in word)


def extract_words(text: str) -> list[str]:
    """Extract words from text, normalize and filter."""
    # Remove URLs, paths, code-like patterns
    text = re.sub(r'https?://\S+', '', text)
    text = re.sub(r'[A-Z]:\\[\w\\]+', '', text)  # Windows paths
    text = re.sub(r'/[\w/]+', '', text)  # Unix paths
    text = re.sub(r'`[^`]+`', '', text)  # Code blocks
    text = re.sub(r'\{[^}]+\}', '', text)  # JSON-like
    text = re.sub(r'<[^>]+>', '', text)  # XML/HTML tags

    # Extract words
    words = re.findall(r'\b[\w]+\b', text.lower())

    # Filter
    filtered = []
    for w in words:
        if len(w) < MIN_WORD_LENGTH:
            continue
        if w in POLISH_STOPWORDS:
            continue
        if w.isdigit():
            continue
        if re.match(r'^[a-f0-9]{8,}$', w):  # UUIDs/hashes
            continue
        filtered.append(w)

    return filtered


def scan_conversation_files(base_path: Path) -> Generator[tuple[str, str], None, None]:
    """Scan all .jsonl files and yield (file, user_message) tuples."""
    for jsonl_file in base_path.rglob("*.jsonl"):
        # Skip agent files (sub-agent conversations)
        if jsonl_file.name.startswith("agent-"):
            continue

        try:
            with open(jsonl_file, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    try:
                        data = json.loads(line.strip())
                        if data.get("type") == "user":
                            msg = data.get("message", {})
                            if isinstance(msg, dict):
                                content = msg.get("content", "")
                                if content and isinstance(content, str):
                                    yield str(jsonl_file), content
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            print(f"Error reading {jsonl_file}: {e}")


def analyze_polish_keywords(base_path: Path, output_path: Path):
    """Analyze user prompts and extract Polish keyword patterns."""
    print("=" * 70)
    print("User Prompt Analysis - Polish Keyword Extraction")
    print("=" * 70)

    all_words = Counter()
    polish_words = Counter()
    prompt_count = 0
    file_count = 0
    seen_files = set()

    print(f"\nScanning: {base_path}\n")

    for file_path, content in scan_conversation_files(base_path):
        if file_path not in seen_files:
            seen_files.add(file_path)
            file_count += 1

        prompt_count += 1
        words = extract_words(content)
        all_words.update(words)

        # Check for Polish words
        for word in words:
            if is_polish_word(word):
                polish_words[word] += 1

        if prompt_count % 500 == 0:
            print(f"  Processed {prompt_count} prompts from {file_count} files...")

    print(f"\n[DONE] Processed {prompt_count} prompts from {file_count} files")
    print(f"  Total unique words: {len(all_words)}")
    print(f"  Words with Polish chars: {len(polish_words)}")

    # Separate analysis
    print("\n" + "=" * 70)
    print("TOP 100 POLISH WORDS (with diacritics)")
    print("=" * 70)

    for word, count in polish_words.most_common(100):
        print(f"  {count:4d}x  {word}")

    # Find action verbs (imperative forms often used in commands)
    # Polish imperatives often end in: -aj, -uj, -ij, -yj, -ań, etc.
    imperative_pattern = re.compile(r'.+(aj|uj|ij|yj|ań|eń|ąć|ić|yć|ować)$')
    imperatives = Counter()

    for word, count in all_words.items():
        if imperative_pattern.match(word) and len(word) >= 4:
            imperatives[word] += count

    print("\n" + "=" * 70)
    print("TOP 50 LIKELY IMPERATIVES/VERBS")
    print("=" * 70)

    for word, count in imperatives.most_common(50):
        print(f"  {count:4d}x  {word}")

    # Common programming/Claude-related Polish terms
    programming_terms = Counter()
    prog_keywords = {
        "napraw", "popraw", "zrób", "stwórz", "usuń", "dodaj", "zmień",
        "sprawdź", "pokaż", "znajdź", "szukaj", "uruchom", "zatrzymaj",
        "commituj", "pushuj", "pulluj", "merguj", "rebajsuj",
        "refaktoruj", "debuguj", "testuj", "deployuj",
        "kod", "plik", "funkcja", "klasa", "błąd", "error",
        "problem", "projekt", "repo", "branch", "commit", "push"
    }

    for word, count in all_words.items():
        for kw in prog_keywords:
            if kw in word:
                programming_terms[word] += count
                break

    print("\n" + "=" * 70)
    print("PROGRAMMING-RELATED POLISH TERMS")
    print("=" * 70)

    for word, count in programming_terms.most_common(50):
        print(f"  {count:4d}x  {word}")

    # Save results to JSON
    results = {
        "stats": {
            "prompts_analyzed": prompt_count,
            "files_scanned": file_count,
            "unique_words": len(all_words),
            "polish_char_words": len(polish_words)
        },
        "top_polish_words": dict(polish_words.most_common(200)),
        "top_imperatives": dict(imperatives.most_common(100)),
        "programming_terms": dict(programming_terms.most_common(100)),
        "all_words_sample": dict(all_words.most_common(500))
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\n[SAVED] Results to: {output_path}")


if __name__ == "__main__":
    base_path = Path(r"C:\Users\DELL\.claude\projects")
    output_path = Path(__file__).parent / "prompt-analysis-results.json"

    analyze_polish_keywords(base_path, output_path)
