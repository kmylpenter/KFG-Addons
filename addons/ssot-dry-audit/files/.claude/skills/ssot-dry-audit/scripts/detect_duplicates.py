#!/usr/bin/env python3
"""SSOT/DRY mechanical scanner.

Walks the given directory and emits a JSON report. Skill consumes it and
adds semantic interpretation (Phase 3). Helper is a fast pre-filter, not
a judge.

Usage:
    python3 detect_duplicates.py [PATH] [--max-file-size BYTES] [--output FILE]
                                 [--compact] [--allow-outside-cwd]

Output: JSON on stdout, or to --output FILE (stdout then carries a 1-line summary —
recommended: full JSON overflows tool-output limits on medium repos).
Errors = JSON with an "error" field on STDOUT; warnings go to stderr. Exit codes:
    0 = ok
    1 = invalid args / not a directory / empty scan
    2 = path traversal attempt (argparse errors also exit 2, usage on stderr)
    130 = interrupted (partial)

SSOT: the installed copy (~/.claude/skills/ssot-dry-audit/scripts/) is the source
of truth; the distribution mirror lives in <repo KFG-Addons>/addons/ssot-dry-audit/
files/.claude/skills/ssot-dry-audit/scripts/ — after ANY edit: cp installed→mirror + diff -q.
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
HELPER_VERSION = "2.2.0"  # 2.2.0: M12 keyword blocklist, M13 PESEL/NIP checksums + raw-line PII scan, M25 truncation{} + locations_total, M26 shell extensions, M41 empty-scan guard, M50 --output/--compact, M60/M78 walk_info (symlinks + unreadable dirs). 2.1.0: C3 in-place HTML masking, M57, M58.

CODE_EXTENSIONS = {
    ".js", ".jsx", ".mjs", ".cjs",
    ".ts", ".tsx",
    ".py", ".gs",
    ".vue", ".svelte",
    ".go", ".rs", ".java", ".kt",
    ".rb", ".php",
    ".html", ".htm", ".css", ".scss",
    ".sh", ".bash", ".zsh",
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

# Unambiguous test-dir segments — matched against the path RELATIVE TO SCAN ROOT
# (an ancestor dir named tests/ ABOVE the scope must not classify the whole scope).
TEST_DIR_HINTS = re.compile(
    r"(^|/)(__tests__|__mocks__|tests?|fixtures?|cypress|playwright|"
    r"i18n|locales|translations)(/|$)",
    re.IGNORECASE,
)
# NOTE (M57): integration/e2e/spec are deliberately NOT dir-matched — they are common
# PRODUCTION dir names (src/integration/ = e.g. Zoho CRM code). Real tests inside such
# dirs are still caught by the test-shaped FILENAME rule in looks_like_test().

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

# Control-flow keywords that FUNCTION_DEF_RE's method-like branch (top-level GAS)
# false-positively matches as "definitions": `for (...) {`, `while (...) {` etc. —
# in JS/GAS these open nearly every file and EVICT real findings via the [:30] cap (M12).
CONTROL_KEYWORDS = {
    "for", "while", "switch", "catch", "if", "else", "do", "return",
    "function", "async", "await", "typeof", "new", "delete", "void",
    "in", "of", "with", "try", "yield",
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

# Secret/PII patterns — values CONTAINING these are REDACTED in occurrences.
# NOT ^$-anchored (except base64-blob): real leaks are EMBEDDED in longer literals
# ("Authorization: Bearer eyJ...", "key=sk_live_...", "url?token=ghp_...") — anchored
# patterns missed them entirely (M58). The WHOLE literal value gets redacted.
SECRET_PATTERNS = [
    (re.compile(r"\bsk_(live|test)_[A-Za-z0-9]{16,}"), "stripe-key"),
    (re.compile(r"\b(AKIA|ASIA)[A-Z0-9]{16}\b"), "aws-key"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"), "jwt"),
    (re.compile(r"\b(ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}"), "github-token"),
    (re.compile(r"://[^/\s]+:[^@\s]+@"), "url-with-credentials"),
    (re.compile(r"^[A-Za-z0-9+/]{40,}={0,2}$"), "base64-blob"),  # anchored ON PURPOSE (FP guard: hashes/shas in code)
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"), "slack-token"),
]

# Polish business identifiers — flagged as their own category.
POLISH_PATTERNS = [
    (re.compile(r"\bPL\d{26}\b"), "iban-pl"),
    (re.compile(r"(?<!\d)\d{11}(?!\d)"), "pesel-or-regon11"),  # 11 digits = PESEL (checksum-validated below)
    (re.compile(r"(?<!\d)\d{10}(?!\d)"), "nip-or-regon"),       # 10 digits = NIP (checksum-validated below)
    (re.compile(r"\b\d{3}-\d{3}-\d{2}-\d{2}\b"), "nip-formatted"),
]


def _pesel_valid(s: str) -> bool:
    """PESEL checksum — bare 11-digit runs are usually timestamps/db-ids, not PII (M13)."""
    if len(s) != 11 or not s.isdigit():
        return False
    weights = (1, 3, 7, 9, 1, 3, 7, 9, 1, 3)
    return (10 - sum(int(a) * w for a, w in zip(s[:10], weights)) % 10) % 10 == int(s[10])


def _nip_valid(s: str) -> bool:
    """NIP checksum (mod-11; control digit may not be 10)."""
    if len(s) != 10 or not s.isdigit():
        return False
    weights = (6, 5, 7, 2, 3, 4, 5, 6, 7)
    c = sum(int(a) * w for a, w in zip(s[:9], weights)) % 11
    return c != 10 and c == int(s[9])


def is_skipped_dir(name: str) -> bool:
    return name in SKIP_DIR_NAMES


def is_skipped_file(path: Path) -> bool:
    return any(p.search(path.name) for p in SKIP_FILE_PATTERNS)


def _testy_filename(path: Path) -> bool:
    stem = path.stem
    return (
        stem.endswith((".test", ".spec", "_test", "_spec"))
        or stem.startswith(("test_", "spec_"))
    )


def looks_like_test(path: Path, root: Path) -> bool:
    """M57: match against the path RELATIVE to the scan root — an ancestor dir
    named tests/ ABOVE the scope must not classify the whole scope as tests.
    Ambiguous segments (integration/e2e/spec) are intentionally not dir-matched
    (production dir names); tests inside them match via the filename rule."""
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path
    if TEST_DIR_HINTS.search(str(rel).replace("\\", "/")):
        return True
    return _testy_filename(path)


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


def walk_files(root: Path, max_size: int) -> tuple[list[Path], dict]:
    """M60/M78: unreadable directories and skipped symlinked dirs are COUNTED and
    reported (walk_info) — a permission-blocked subtree used to vanish silently,
    presenting a partial scan as complete."""
    out: list[Path] = []
    walk_errors: list[str] = []
    sym_dirs = 0
    size_skipped = 0
    for dirpath, dirnames, filenames in os.walk(
        root, onerror=lambda e: walk_errors.append(str(getattr(e, "filename", e)))
    ):
        kept = []
        for d in dirnames:
            if is_skipped_dir(d):
                continue
            if (Path(dirpath) / d).is_symlink():
                sym_dirs += 1   # not traversed (followlinks=False — cycle safety); report it
                continue
            kept.append(d)
        dirnames[:] = kept
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix.lower() not in CODE_EXTENSIONS:
                continue
            if is_skipped_file(p):
                continue
            try:
                if p.stat().st_size > max_size:
                    size_skipped += 1
                    print(
                        f"warn: skipping {p.relative_to(root)} (size > {max_size})",
                        file=sys.stderr,
                    )
                    continue
            except OSError:
                continue
            out.append(p)
    walk_info = {
        "dirs_unreadable": len(walk_errors),
        "dirs_unreadable_sample": walk_errors[:10],
        "dirs_symlinked_skipped": sym_dirs,
        "files_size_skipped": size_skipped,
    }
    return out, walk_info


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


HTML_CODE_BODY_RE = re.compile(
    r"<(script|style)\b[^>]*>(.*?)</\1\s*>", re.DOTALL | re.IGNORECASE
)


def get_scan_text(p: Path, raw: str) -> str:
    """For .html/.htm keep ONLY <script>/<style> bodies IN PLACE: markup is blanked
    with spaces, newlines preserved — so every reported lineno points at the REAL
    line of the original file. (C3 fix: the old concatenated-extract approach made
    .html line numbers index the extract, off by the tag offset — for the user's
    5000-line GAS HTML files that meant locations off by thousands of lines.)"""
    if p.suffix.lower() not in {".html", ".htm"}:
        return raw
    keep = bytearray(len(raw))
    for m in HTML_CODE_BODY_RE.finditer(raw):
        for i in range(m.start(2), m.end(2)):
            keep[i] = 1
    out = []
    for i, ch in enumerate(raw):
        if ch == "\n":
            out.append("\n")          # line structure preserved 1:1
        elif keep[i]:
            out.append(ch)
        else:
            out.append(" ")           # markup masked out — never reaches the scan
    return "".join(out)


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
    """Comment-marker grammar: 'py' = '#'-style (Python, shell), 'c' = '//'-style."""
    return "py" if p.suffix.lower() in {".py", ".sh", ".bash", ".zsh"} else "c"


def find_string_literals(files_with_text: list[tuple[Path, str]]) -> tuple[list[dict], int]:
    occurrences: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
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
                "locations_total": len(locs),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["occurrences"], x["value"]))
    return findings[:50], len(findings)


def find_number_literals(files_with_text: list[tuple[Path, str]]) -> tuple[list[dict], int]:
    occurrences: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
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
                "locations_total": len(locs),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["occurrences"], x["value"]))
    return findings[:30], len(findings)


def find_duplicate_function_names(files_with_text: list[tuple[Path, str]]) -> tuple[list[dict], int]:
    names: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in FUNCTION_DEF_RE.finditer(line):
                name = next((g for g in m.groups() if g), None)
                if not name or len(name) < 3:
                    continue
                if name in COMMON_FUNCTION_NAMES or name.lower() in CONTROL_KEYWORDS:
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
                "locations_total": len(locs),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["files"], x["name"]))
    return findings[:30], len(findings)


def find_duplicate_types(files_with_text: list[tuple[Path, str]]) -> tuple[list[dict], int]:
    names: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
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
                "locations_total": len(locs),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["files"], x["name"]))
    return findings[:30], len(findings)


def find_duplicate_blocks(files_with_text: list[tuple[Path, str]], window: int = 5) -> tuple[list[dict], int]:
    """Hash sliding windows of `window` non-empty normalized lines per file.
    Reports hashes that appear in 2+ different files."""
    hashes: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for p, text in files_with_text:
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
                "locations_total": len(locs),
                "locations": locs[:10],
            })
    findings.sort(key=lambda x: (-x["occurrences"], x["hash"]))
    return findings[:20], len(findings)


def find_polish_business_ids(files_with_text: list[tuple[Path, str]]) -> tuple[list[dict], int]:
    """Polish business identifiers (PESEL/NIP/IBAN) — flagged as critical because a
    hardcoded id is a GDPR/RODO violation regardless of duplication. M13 hardening:
    (a) scan the RAW line — a PESEL inside a comment is still a violation, so the
    comment stripper must not hide it; (b) digit-run kinds require a VALID checksum
    (bare 10/11-digit runs are usually timestamps/phones/db-ids, not PII)."""
    findings: list[dict] = []
    for p, text in files_with_text:
        for lineno, raw in enumerate(text.splitlines(), 1):
            for pat, kind in POLISH_PATTERNS:
                for m in pat.finditer(raw):
                    digits = re.sub(r"\D", "", m.group(0))
                    if kind == "pesel-or-regon11" and not _pesel_valid(digits):
                        continue
                    if kind in ("nip-or-regon", "nip-formatted") and not _nip_valid(digits):
                        continue
                    findings.append({
                        "kind": kind,
                        "value_redacted": "[REDACTED:" + kind + "]",
                        "location": [str(p), lineno],
                    })
    return findings[:50], len(findings)


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
    p.add_argument(
        "--output", metavar="FILE", default=None,
        help="Write JSON to FILE (atomic tmp+rename); stdout gets a 1-line summary. "
             "Recommended — full JSON overflows tool-output limits on medium repos (M50).",
    )
    p.add_argument(
        "--compact", action="store_true",
        help="Compact JSON (no indent, tight separators) — ~40%% smaller.",
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

    if args.max_file_size < 1024:
        print(json.dumps({
            "schema_version": SCHEMA_VERSION,
            "error": f"--max-file-size {args.max_file_size} < 1024 would skip every file (M41)",
        }))
        return 1

    files, walk_info = walk_files(root, args.max_file_size)
    files_with_text: list[tuple[Path, str]] = []
    for p in files:
        raw = read_text(p, root)
        if raw is None:
            continue
        files_with_text.append((p, get_scan_text(p, raw)))

    if not files_with_text:
        print(json.dumps({
            "schema_version": SCHEMA_VERSION,
            "error": "no files scanned (wrong scope? extensions? size limit?) — a 'clean' report here would be FALSE (M41)",
            "walk_info": walk_info,
        }))
        return 1

    # Test filtering happens ONCE here (not in every finder) — exclusions are
    # reported so Phase 3 can see what the helper did NOT scan (M57).
    code_files = [(p, t) for (p, t) in files_with_text
                  if not looks_like_test(p, root)]
    files_excluded_as_test = len(files_with_text) - len(code_files)

    project = detect_project_type(root)

    ds, ds_total = find_string_literals(code_files)
    dn, dn_total = find_number_literals(code_files)
    df, df_total = find_duplicate_function_names(code_files)
    dt, dt_total = find_duplicate_types(code_files)
    db, db_total = find_duplicate_blocks(code_files)
    pii, pii_total = find_polish_business_ids(code_files)

    report = {
        "schema_version": SCHEMA_VERSION,
        "helper_version": HELPER_VERSION,
        "scope": str(root),
        "files_scanned": len(files_with_text),
        "files_skipped": len(files) - len(files_with_text),
        "files_excluded_as_test": files_excluded_as_test,
        "walk_info": walk_info,
        "project": project,
        "findings": {
            "duplicate_strings": ds,
            "duplicate_numbers": dn,
            "duplicate_function_names": df,
            "duplicate_type_names": dt,
            "duplicate_code_blocks": db,
            "polish_business_ids": pii,
        },
        # M25: caps are no longer silent — Phase 3 must re-grep truncated categories
        # (and per-finding locations where locations_total > 10) before refactor proposals.
        "truncation": {
            "duplicate_strings": {"returned": len(ds), "total_found": ds_total},
            "duplicate_numbers": {"returned": len(dn), "total_found": dn_total},
            "duplicate_function_names": {"returned": len(df), "total_found": df_total},
            "duplicate_type_names": {"returned": len(dt), "total_found": dt_total},
            "duplicate_code_blocks": {"returned": len(db), "total_found": db_total},
            "polish_business_ids": {"returned": len(pii), "total_found": pii_total},
            "note": "locations per finding capped at 10 — see locations_total; re-grep to expand",
        },
        "notes": [
            "Helper output is RAW. Skill (Phase 3) must filter false positives semantically.",
            "Test files / mocks / i18n / fixtures excluded automatically (count: files_excluded_as_test; matched vs SCAN ROOT, ambiguous dirs need test-shaped filename).",
            "Secret-shaped strings redacted before output (patterns match EMBEDDED secrets too).",
            "Polish PII digit-kinds are CHECKSUM-validated (PESEL/NIP) and scanned on RAW lines incl. comments.",
            "HTML files: <script>/<style> bodies scanned IN PLACE — line numbers match the original file.",
            "Unreadable/symlinked dirs are counted in walk_info — a partial walk is disclosed, not hidden.",
        ],
    }

    def render(ascii_fallback: bool = False) -> str:
        return json.dumps(
            report,
            indent=None if args.compact else 2,
            ensure_ascii=ascii_fallback,
            separators=(",", ":") if args.compact else None,
        )

    if args.output:
        tmp_path = args.output + ".tmp"
        Path(tmp_path).write_text(render(), encoding="utf-8")
        os.replace(tmp_path, args.output)   # atomic: tmp + rename (M50)
        print(json.dumps({
            "written": args.output,
            "schema_version": SCHEMA_VERSION,
            "files_scanned": report["files_scanned"],
        }))
    else:
        try:
            print(render())
        except UnicodeEncodeError:
            print(render(ascii_fallback=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print(json.dumps({"schema_version": SCHEMA_VERSION, "error": "interrupted", "partial": True}))
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)
