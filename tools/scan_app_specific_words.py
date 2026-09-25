#!/usr/bin/env python3
"""Fails if any Motion app name leaks into shared package library CODE.

Scope is deliberately narrow, matching 02-MOTION-AILESI-ORKESTRASYON.md §7
step 3 ("App-specific kelime veya content ID core API'sine girmez"):

  - Only packages/*/lib/**/*.dart — the shipped API surface. pubspec.yaml,
    README, docs/ and test/ are out of scope: they may legitimately name
    consumers in prose (motion_core's own pubspec.yaml description lists all
    five apps by name — that's a consumer-relationship statement, not an
    API leak).
  - Only CODE, not comments. `//`, `///` and `/* */` comments are stripped
    before matching. motion_core's shipped source carries many "why" doc
    comments that cite which app's real-world measurement motivated a design
    decision (e.g. "rejecting 32% of correct frames on Gravita's D1 footage,
    G-018") — that is exactly the non-obvious-WHY documentation a reader
    needs, not app-specific behavior leaking into the API, and this scanner
    must not force it to be stripped out to pass CI. A bare `//` inside a
    string literal is not treated as a comment start.
  - A small, explicit, content-keyed ALLOWLIST (scan_app_specific_words_
    allowlist.txt) covers reviewed validator diagnostics and the fixed
    Motion account product-ID enum. That enum defines an identity boundary,
    not app-specific exercise behavior. The allowlist is keyed by exact
    line text: if it changes, the hit reappears in CI for review.

A hit inside actual code that is NOT in the allowlist — an identifier, a
branch condition, a new hardcoded string literal used by logic — is exactly
what this gate exists to catch.
"""
import re
import sys
from pathlib import Path

FORBIDDEN_WORDS = ["lissom", "jablab", "gravita", "ostinato", "choreia"]

REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGES_DIR = REPO_ROOT / "packages"
ALLOWLIST_PATH = Path(__file__).resolve().with_name("scan_app_specific_words_allowlist.txt")

_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)


def strip_line_comment(line):
    """Removes a trailing `//`/`///` line comment, leaving string literal
    contents (including any `//` inside them) intact."""
    in_string = None
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if in_string:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = ch
            i += 1
            continue
        if ch == "/" and i + 1 < n and line[i + 1] == "/":
            return line[:i]
        i += 1
    return line


def code_only(text):
    without_block_comments = _BLOCK_COMMENT_RE.sub("", text)
    return "\n".join(strip_line_comment(line) for line in without_block_comments.splitlines())


def build_pattern():
    words = "|".join(re.escape(w) for w in FORBIDDEN_WORDS)
    return re.compile(rf"\b({words})\b", re.IGNORECASE)


def load_allowlist():
    """Returns {(relative_path_str, line_no): exact_line_text}."""
    entries = {}
    if not ALLOWLIST_PATH.exists():
        return entries
    for raw in ALLOWLIST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        path_part, line_no_part, text_part = line.split(":", 2)
        entries[(path_part, int(line_no_part))] = text_part
    return entries


def find_violations(root=PACKAGES_DIR):
    pattern = build_pattern()
    violations = []
    for lib_dart_file in sorted(root.glob("*/lib/**/*.dart")):
        raw_text = lib_dart_file.read_text(encoding="utf-8", errors="replace")
        code_text = code_only(raw_text)
        for line_no, line in enumerate(code_text.splitlines(), start=1):
            match = pattern.search(line)
            if match:
                violations.append((lib_dart_file, line_no, match.group(0), line.strip()))
    return violations


def main():
    if not PACKAGES_DIR.is_dir():
        print(f"FAIL: packages dir not found at {PACKAGES_DIR}", file=sys.stderr)
        return 2

    allowlist = load_allowlist()
    violations = find_violations()
    scanned = sorted(PACKAGES_DIR.glob("*/lib/**/*.dart"))
    print(f"Scanned {len(scanned)} file(s) under packages/*/lib/ (code only, comments stripped) for {FORBIDDEN_WORDS}")

    hard_failures = []
    allowed_hits = []
    matched_allowlist_keys = set()
    for path, line_no, matched, line in violations:
        rel = str(path.relative_to(REPO_ROOT))
        key = (rel, line_no)
        if key in allowlist and allowlist[key] == line:
            allowed_hits.append((rel, line_no, matched))
            matched_allowlist_keys.add(key)
        else:
            hard_failures.append((rel, line_no, matched, line))

    if allowed_hits:
        print(f"\n{len(allowed_hits)} hit(s) covered by the reviewed allowlist:")
        for rel, line_no, matched in allowed_hits:
            print(f"  {rel}:{line_no}: matched '{matched}' (allowlisted)")

    stale_allowlist_keys = set(allowlist) - matched_allowlist_keys
    if stale_allowlist_keys:
        print(f"\nWARNING: {len(stale_allowlist_keys)} allowlist entr(y/ies) no longer match "
              "any current line (stale — safe to remove):", file=sys.stderr)
        for rel, line_no in sorted(stale_allowlist_keys):
            print(f"  {rel}:{line_no}", file=sys.stderr)

    if hard_failures:
        print(f"\nFAIL: {len(hard_failures)} app-specific reference(s) found in shared library "
              "code, not covered by the reviewed allowlist:\n")
        for rel, line_no, matched, line in hard_failures:
            print(f"  {rel}:{line_no}: matched '{matched}' -- {line}")
        return 1

    print("\nPASS: no unreviewed app-specific word found in packages/*/lib/ code")
    return 0


if __name__ == "__main__":
    sys.exit(main())
