#!/usr/bin/env python3
"""SSOT/DRY mechanical scanner.

Walks the given directory and emits a JSON report. Skill consumes it and
adds semantic interpretation (Phase 3). Helper is a fast pre-filter, not
a judge.

Usage:
    python3 detect_duplicates.py [PATH] [--max-file-size BYTES]

Output: JSON on stdout. Errors go to stderr; exit codes:
    0 = ok
    1 = invalid args / not a directory
    2 = path traversal attempt
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

SCHEMA_VERSION = "2.0"
HELPER_VERSION = "2.0.0"

CODE_EXTENSIONS = {
    ".js", ".jsx", ".mjs", ".cjs",
    ".ts", ".tsx",
    ".py", ".gs",
    ".vue", ".svelte",
    ".go", ".rs", ".java", ".kt",
    ".rb", ".php",
    ".html", ".htm", ".css", ".scss",
}

SKIP_DIR_NAMES = {
    "node_modules", "dist", "build", ".next", ".nuxt",
    "coverage", "__pycache__", ".pytest_cache",
    ".git", ".svn", ".hg",
    "vendor", "venv", ".venv", "env",
    "out", "target", ".turbo",
}

SKIP_FILE_PATTERNS = [
    re.compile(r"\.lock$"),
    re.compile(r"package-lock\.json$"),
    re.compile(r"yarn\.lock$"),
    re.compile(r"poetry\.lock$"),
    re.compile(r"\.min\.(js|css)$"),
    re.compile(r"\.bundle\.(js|css)$"),
    re.compile(r"\.map$"),
]

TEST_PATH_HINTS = re.compile(
    r"(^|/)(__tests__|__mocks__|tests?|spec|fixtures?|cypress|playwright|"
    r"e2e|integration|i18n|locales|translations)(/|$)",
    re.IGNORECASE,
)

# Escape-aware string literal regex covering ', ", ` — captures content (group 1, 2 or 3).
STRING_LITERAL_RE = re.compile(
    r"""'((?:\\.|[^'\n\\]){2,300})'"""
    r"""|"((?:\\.|[^"\n\\]){2,300})\""""
    r"""|`((?:\\.|[^`\\]){2,300})`""",
    re.DOTALL,
)

# Float-aware: matches integers and decimals not preceded/followed by identifier/dot.
NUMBER_LITERAL_RE = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")

FUNCTION_DEF_RE = re.compile(
    r"\bdef\s+([a-zA-Z_]\w*)"                                    # Python
    r"|\bfunction\s+([a-zA-Z_$][\w$]*)"                          # JS classic
    r"|\bfn\s+([a-zA-Z_]\w*)"                                    # Rust
    r"|\bfunc\s+(?:\([^)]*\)\s+)?([a-zA-Z_]\w*)"                 # Go (with optional receiver)
    r"|\bfun\s+([a-zA-Z_]\w*)"                                   # Kotlin
    r"|(?:const|let|var)\s+([a-zA-Z_$][\w$]*)\s*=\s*(?:async\s+)?(?:\([^)]*\)|\w+)\s*=>"  # JS arrow
    r"|^\s*([a-zA-Z_$][\w$]*)\s*\([^)]*\)\s*\{"                  # method-like (top-level GAS)
)

TYPE_DEF_RE = re.compile(
    r"\b(?:interface|type|class|struct|enum)\s+([a-zA-Z_]\w*)"
)

COMMON_NUMBERS = {
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10",
    "200", "201", "204", "301", "302", "400", "401", "403", "404", "500",
}

COMMON_STRINGS = {
    # Generic boilerplate
    "true", "false", "null", "undefined", "use strict",
    "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD",
    "application/json", "text/html", "text/plain", "utf-8", "UTF-8",
    # Google Apps Script API namespaces (top sources of false positives in user's stack)
    "SpreadsheetApp", "DocumentApp", "DriveApp", "FormApp", "SitesApp",
    "PropertiesService", "CacheService", "LockService",
    "UrlFetchApp", "HtmlService", "ScriptApp", "Session", "Utilities",
    "ContentService", "GmailApp", "CalendarApp",
    "getActiveSpreadsheet", "getActiveSheet", "getActive",
    "getScriptLock", "getDocumentLock", "getUserLock",
    "getRange", "getValues", "setValues", "getValue", "setValue",
    "getSheetByName", "getDataRange", "getLastRow", "getLastColumn",
    "doGet", "doPost", "onOpen", "onEdit", "onFormSubmit",
}

COMMON_FUNCTION_NAMES = {
    # Generic entry points
    "main", "init", "render", "handler", "default", "setup",
    "constructor", "toString", "valueOf",
    # Framework lifecycle
    "mount", "unmount", "componentDidMount", "componentWillUnmount",
    "loader", "action", "getServerSideProps", "getStaticProps",
    # GAS triggers (these are namespaced per project, not duplicates)
    "doGet", "doPost", "onOpen", "onEdit", "onFormSubmit", "onChange",
}

# Secret/PII patterns — values matching these are REDACTED in occurrences.
SECRET_PATTERNS = [
    (re.compile(r"^sk_(live|test)_[A-Za-z0-9]{16,}$"), "stripe-key"),
    (re.compile(r"^(AKIA|ASIA)[A-Z0-9]{16}$"), "aws-key"),
    (re.compile(r"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"), "jwt"),
    (re.compile(r"^(ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}$"), "github-token"),
    (re.compile(r"://[^/\s]+:[^@\s]+@"), "url-with-credentials"),
    (re.compile(r"^[A-Za-z0-9+/]{40,}={0,2}$"), "base64-blob"),
    (re.compile(r"^xox[baprs]-[A-Za-z0-9-]{10,}$"), "slack-token"),
]

# Polish business identifiers — flagged as their own category.
POLISH_PATTERNS = [
    (re.compile(r"\bPL\d{26}\b"), "iban-pl"),
    (re.compile(r"(?<!\d)\d{11}(?!\d)"), "pesel-or-regon11"),  # PESEL 11 / REGON 14 (handled separately)
    (re.compile(r"(?<!\d)\d{10}(?!\d)"), "nip-or-regon"),       # NIP 10 / REGON 9 ambiguous
    (re.compile(r"\b\d{3}-\d{3}-\d{2}-\d{2}\b"), "nip-formatted"),
]


def is_skipped_dir(name: str) -> bool:
    return name in SKIP_DIR_NAMES


def is_skipped_file(path: Path) -> bool:
    return any(p.search(path.name) for p in SKIP_FILE_PATTERNS)


def looks_like_test(path: Path) -> bool:
    s = str(path).replace("\\", "/")
    if TEST_PATH_HINTS.search(s):
        return True
    stem = path.stem
    return (
        stem.endswith((".test", ".spec", "_test", "_spec"))
        or stem.startswith(("test_", "spec_"))
    )


def is_secret_shaped(value: str) -> str | None:
    for pat, label in SECRET_PATTERNS:
        if pat.search(value):
            return label
    return None


def redact(value: str) -> str:
    label = is_secret_shaped(value)
    if label:
        return f"[REDACTED:{label}]"
    return value


def normalize_unicode(text: str) -> str:
    """Polish strings need NFC normalization to avoid false negatives between NFC/NFD."""
    return unicodedata.normalize("NFC", text)


def walk_files(root: Path, max_size: int) -> list[Path]:
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
        dirnames[:] = [d for d in dirnames if not is_skipped_dir(d)]
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix.lower() not in CODE_EXTENSIONS:
                continue
            if is_skipped_file(p):
                continue
            try:
                if p.stat().st_size > max_size:
                    print(
                        f"warn: skipping {p.relative_to(root)} (size > {max_size})",
                        file=sys.stderr,
                    )
                    continue
            except OSError:
                continue
            out.append(p)
    return out


def read_text(p: Path, root: Path) -> str | None:
    try:
        text = p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        try:
            print(f"warn: cannot read {p.relative_to(root)}", file=sys.stderr)
        except ValueError:
            pass
        return None
    # Quick binary heuristic: too many NUL bytes in first 4KB.
    head = text[:4096]
    if head.count("\x00") > 5:
        return None
    return normalize_unicode(text)


def extract_html_scripts(text: str) -> str:
    """Concatenate <script> bodies so duplicate JS in HTML pages is detectable."""
    matches = re.findall(
        r"<script\b[^>]*>(.*?)</script>", text, re.DOTALL | re.IGNORECASE
    )
    return "\n".join(matches)


def extract_html_styles(text: str) -> str:
    matches = re.findall(
        r"<style\b[^>]*>(.*?)</style>", text, re.DOTALL | re.IGNORECASE
    )
    return "\n".join(matches)


def get_scan_text(p: Path, raw: str) -> str:
    """For .html/.htm, strip markup and keep only embedded JS/CSS so duplicate
    detection runs on the actual code, not the page chrome."""
    if p.suffix.lower() in {".html", ".htm"}:
        return extract_html_scripts(raw) + "\n" + extract_html_styles(raw)
    return raw


def strip_line_comments(line: str, lang: str) -> str:
    """Strip trailing line comments. Keep inside strings — use a simple state machine."""
    if lang == "py":
        markers = ["#"]
    else:
        markers = ["//"]
    out = []
    in_single = in_double = in_back = False
    i = 0
    while i < len(line):
        ch = line[i]
        if not (in_single or in_double or in_back):
            for m in markers:
                if line.startswith(m, i):
                    return "".join(out)
        if ch == "'" and not (in_double or in_back):
            in_single = not in_single
        elif ch == '"' and not (in_single or in_back):
            in_double = not in_double
        elif ch == "`" and not (in_single or in_double):
            in_back = not in_back
        out.append(ch)
        i += 1
    return "".join(out)


def lang_of(p: Path) -> str:
    return "py" if p.suffix == ".py" else "c"


def find_string_literals(files_with_text: list[tuple[Path, str]]) -> list[dict]:
    occurrences: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
        if looks_like_test(p):
            continue
        lang = lang_of(p)
        for lineno, line in enumerate(text.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith(("//", "#", "*", "/*")):
                continue
            line_no_comment = strip_line_comments(line, lang)
            for m in STRING_LITERAL_RE.finditer(line_no_comment):
                lit = m.group(1) or m.group(2) or m.group(3)
                if not lit or lit in COMMON_STRINGS:
                    continue
                occurrences[lit].append((str(p), lineno))

    findings: list[dict] = []
    for lit, locs in occurrences.items():
        files_seen = {loc[0] for loc in locs}
        if len(locs) >= 3 and len(files_seen) >= 2:
            label = is_secret_shaped(lit)
            findings.append({
                "value": redact(lit),
                "secret_kind": label,
                "occurrences": len(locs),
                "files": len(files_seen),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["occurrences"], x["value"]))
    return findings[:50]


def find_number_literals(files_with_text: list[tuple[Path, str]]) -> list[dict]:
    occurrences: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
        if looks_like_test(p):
            continue
        lang = lang_of(p)
        for lineno, line in enumerate(text.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith(("//", "#", "*", "/*")):
                continue
            line_no_comment = strip_line_comments(line, lang)
            for m in NUMBER_LITERAL_RE.finditer(line_no_comment):
                num = m.group(1)
                if num in COMMON_NUMBERS:
                    continue
                occurrences[num].append((str(p), lineno))

    findings: list[dict] = []
    for num, locs in occurrences.items():
        files_seen = {loc[0] for loc in locs}
        # Lower threshold for floats (likely business values like 0.23 VAT).
        is_float = "." in num
        threshold_occ = 2 if is_float else 3
        if len(locs) >= threshold_occ and len(files_seen) >= 2:
            findings.append({
                "value": num,
                "is_float": is_float,
                "occurrences": len(locs),
                "files": len(files_seen),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["occurrences"], x["value"]))
    return findings[:30]


def find_duplicate_function_names(files_with_text: list[tuple[Path, str]]) -> list[dict]:
    names: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
        if looks_like_test(p):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in FUNCTION_DEF_RE.finditer(line):
                name = next((g for g in m.groups() if g), None)
                if not name or len(name) < 3:
                    continue
                if name in COMMON_FUNCTION_NAMES:
                    continue
                names[name].append((str(p), lineno))

    findings: list[dict] = []
    for name, locs in names.items():
        files_seen = {loc[0] for loc in locs}
        if len(files_seen) >= 2:
            findings.append({
                "name": name,
                "occurrences": len(locs),
                "files": len(files_seen),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["files"], x["name"]))
    return findings[:30]


def find_duplicate_types(files_with_text: list[tuple[Path, str]]) -> list[dict]:
    names: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
        if looks_like_test(p):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in TYPE_DEF_RE.finditer(line):
                name = m.group(1)
                if len(name) < 3:
                    continue
                names[name].append((str(p), lineno))

    findings: list[dict] = []
    for name, locs in names.items():
        files_seen = {loc[0] for loc in locs}
        if len(files_seen) >= 2:
            findings.append({
                "name": name,
                "occurrences": len(locs),
                "files": len(files_seen),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["files"], x["name"]))
    return findings[:30]


def find_duplicate_blocks(files_with_text: list[tuple[Path, str]], window: int = 5) -> list[dict]:
    """Hash sliding windows of `window` non-empty normalized lines per file.
    Reports hashes that appear in 2+ different files."""
    hashes: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
        if looks_like_test(p):
            continue
        lang = lang_of(p)
        lines: list[str] = []
        line_numbers: list[int] = []
        for lineno, raw in enumerate(text.splitlines(), 1):
            stripped = strip_line_comments(raw, lang).strip()
            if not stripped or stripped.startswith(("*", "/*")):
                continue
            normalized = re.sub(r"\s+", " ", stripped)
            lines.append(normalized)
            line_numbers.append(lineno)
        seen_in_file: set[str] = set()
        for i in range(len(lines) - window + 1):
            chunk = "\n".join(lines[i:i + window])
            if len(chunk) < 60:
                continue
            h = hashlib.sha256(chunk.encode("utf-8")).hexdigest()[:32]
            key = f"{p}:{h}"
            if key in seen_in_file:
                continue
            seen_in_file.add(key)
            hashes[h].append((str(p), line_numbers[i]))

    findings: list[dict] = []
    for h, locs in hashes.items():
        files_seen = {loc[0] for loc in locs}
        if len(files_seen) >= 2:
            findings.append({
                "hash": h,
                "window_lines": window,
                "occurrences": len(locs),
                "files": len(files_seen),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["occurrences"], x["hash"]))
    return findings[:20]


def find_polish_business_ids(files_with_text: list[tuple[Path, str]]) -> list[dict]:
    """Polish business identifiers (PESEL/NIP/REGON/IBAN) — flagged ALWAYS as critical
    because hardcoded ids are GDPR/RODO violation regardless of duplication."""
    findings: list[dict] = []
    for p, text in files_with_text:
        if looks_like_test(p):
            continue
        lang = lang_of(p)
        for lineno, raw in enumerate(text.splitlines(), 1):
            line = strip_line_comments(raw, lang)
            for pat, kind in POLISH_PATTERNS:
                for m in pat.finditer(line):
                    findings.append({
                        "kind": kind,
                        "value_redacted": "[REDACTED:" + kind + "]",
                        "location": [str(p), lineno],
                    })
    return findings[:50]


def detect_project_type(root: Path) -> dict:
    markers = {
        "package.json": "javascript/typescript",
        "pyproject.toml": "python",
        "requirements.txt": "python",
        "Cargo.toml": "rust",
        "go.mod": "go",
        "appsscript.json": "google-apps-script",
        "Gemfile": "ruby",
        "composer.json": "php",
    }
    # Walk up to find project root markers (scope may be a subdir).
    detected: list[str] = []
    found_at: Path | None = None
    cur: Path | None = root
    while cur is not None and cur != cur.parent:
        for marker, kind in markers.items():
            if (cur / marker).exists() and kind not in detected:
                detected.append(kind)
                found_at = cur
        if detected:
            break
        cur = cur.parent
    return {
        "types": detected or ["unknown"],
        "project_root": str(found_at) if found_at else None,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="detect_duplicates.py",
        description="SSOT/DRY mechanical scanner for ssot-dry-audit skill.",
    )
    p.add_argument("path", nargs="?", default=".", help="Directory to scan (default: cwd)")
    p.add_argument(
        "--max-file-size", type=int, default=1_000_000,
        help="Skip files larger than this (bytes). Default 1MB.",
    )
    p.add_argument(
        "--allow-outside-cwd", action="store_true",
        help="Allow scanning outside current working directory (off by default).",
    )
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    cwd = Path.cwd().resolve()
    root = Path(args.path).resolve()
    if not root.is_dir():
        print(json.dumps({
            "schema_version": SCHEMA_VERSION,
            "error": f"not a directory: {root}",
        }))
        return 1
    if not args.allow_outside_cwd:
        try:
            root.relative_to(cwd)
        except ValueError:
            print(json.dumps({
                "schema_version": SCHEMA_VERSION,
                "error": f"path outside cwd: {root} (use --allow-outside-cwd to override)",
            }))
            return 2

    files = walk_files(root, args.max_file_size)
    files_with_text: list[tuple[Path, str]] = []
    for p in files:
        raw = read_text(p, root)
        if raw is None:
            continue
        files_with_text.append((p, get_scan_text(p, raw)))

    project = detect_project_type(root)

    report = {
        "schema_version": SCHEMA_VERSION,
        "helper_version": HELPER_VERSION,
        "scope": str(root),
        "files_scanned": len(files_with_text),
        "files_skipped": len(files) - len(files_with_text),
        "project": project,
        "findings": {
            "duplicate_strings": find_string_literals(files_with_text),
            "duplicate_numbers": find_number_literals(files_with_text),
            "duplicate_function_names": find_duplicate_function_names(files_with_text),
            "duplicate_type_names": find_duplicate_types(files_with_text),
            "duplicate_code_blocks": find_duplicate_blocks(files_with_text),
            "polish_business_ids": find_polish_business_ids(files_with_text),
        },
        "notes": [
            "Helper output is RAW. Skill (Phase 3) must filter false positives semantically.",
            "Test files / mocks / i18n / fixtures excluded automatically.",
            "Secret-shaped strings redacted before output.",
            "Polish PII/business IDs flagged unconditionally (RODO).",
            "HTML files: only <script> and <style> bodies are scanned.",
        ],
    }
    try:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    except UnicodeEncodeError:
        print(json.dumps(report, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print(json.dumps({"schema_version": SCHEMA_VERSION, "error": "interrupted", "partial": True}))
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)
