"""Proves the app-specific word scanner actually has teeth: it must catch a
real code-level leak, ignore a comment-only mention, and ignore an
allowlisted pre-existing hit only when the line text still matches exactly.

Run: python3 -m unittest tools/tests/test_scan_app_specific_words.py -v
(stdlib-only — no pytest/venv dependency, so it can run directly in CI.)
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scan_app_specific_words as scanner  # noqa: E402


def _write(root, relative_path, content):
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


class CodeOnlyStrippingTest(unittest.TestCase):
    def test_line_comment_is_removed(self):
        self.assertEqual(scanner.strip_line_comment("final x = 1; // Gravita note"), "final x = 1; ")

    def test_doc_comment_is_removed(self):
        self.assertEqual(scanner.strip_line_comment("/// see Gravita ADR-005"), "")

    def test_double_slash_inside_string_literal_is_preserved(self):
        line = "final url = 'https://example.com/gravita';"
        self.assertEqual(scanner.strip_line_comment(line), line)

    def test_block_comment_spanning_lines_is_removed(self):
        text = "int a = 1;\n/* mentions Gravita\n across lines */\nint b = 2;"
        result = scanner.code_only(text)
        self.assertNotIn("Gravita", result)
        self.assertIn("int a = 1;", result)
        self.assertIn("int b = 2;", result)


class FindViolationsTest(unittest.TestCase):
    def test_catches_a_real_code_level_reference(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "motion_feedback/lib/src/leaky.dart",
                "String pick(String appId) {\n"
                "  if (appId == 'lissom') return 'special-case';\n"
                "  return 'default';\n"
                "}\n",
            )
            violations = scanner.find_violations(root=root)
            self.assertEqual(len(violations), 1)
            _path, line_no, matched, _line = violations[0]
            self.assertEqual(line_no, 2)
            self.assertEqual(matched.lower(), "lissom")

    def test_catches_a_reference_in_motion_content_library(self):
        """The new package must stay inside the scanner's shipped-code scope."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            leaked_path = _write(
                root,
                "motion_content/lib/src/leaky_catalog.dart",
                "const productSpecificCourse = 'ostinato';\n",
            )

            violations = scanner.find_violations(root=root)

            self.assertEqual(
                violations,
                [(leaked_path, 1, "ostinato", "const productSpecificCourse = 'ostinato';")],
            )

    def test_ignores_a_comment_only_mention(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "motion_core/lib/src/rationale.dart",
                "// Generalised from a bug JabLab hit in production (J-092).\n"
                "int computeSomethingGeneric() => 1;\n",
            )
            violations = scanner.find_violations(root=root)
            self.assertEqual(violations, [])

    def test_ignores_files_outside_lib(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(root, "motion_feedback/test/leaky_test.dart", "// choreia\n")
            _write(root, "motion_feedback/README.md", "Used by choreia and others.\n")
            violations = scanner.find_violations(root=root)
            self.assertEqual(violations, [])


class AllowlistTest(unittest.TestCase):
    def test_allowlist_only_suppresses_an_exact_line_text_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            allowlist_path = root / "allowlist.txt"
            allowlist_path.write_text(
                "motion_core/lib/src/rationale.dart:2:issues.add('Gravita rule violated');\n",
                encoding="utf-8",
            )
            original_path = scanner.ALLOWLIST_PATH
            scanner.ALLOWLIST_PATH = allowlist_path
            try:
                allowlist = scanner.load_allowlist()
            finally:
                scanner.ALLOWLIST_PATH = original_path
            self.assertEqual(
                allowlist[("motion_core/lib/src/rationale.dart", 2)],
                "issues.add('Gravita rule violated');",
            )

    def test_stale_allowlist_entry_no_longer_matches_changed_text(self):
        # A content-keyed allowlist entry for old text must NOT silently
        # suppress a hit on a line whose text has since changed — otherwise
        # an edit could smuggle a *new* violation past a *stale* exception.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            allowlist_path = root / "allowlist.txt"
            allowlist_path.write_text(
                "motion_core/lib/src/rationale.dart:2:issues.add('old Gravita text');\n",
                encoding="utf-8",
            )
            original_path = scanner.ALLOWLIST_PATH
            scanner.ALLOWLIST_PATH = allowlist_path
            try:
                allowlist = scanner.load_allowlist()
            finally:
                scanner.ALLOWLIST_PATH = original_path
            current_line = "issues.add('completely different Gravita text');"
            key = ("motion_core/lib/src/rationale.dart", 2)
            self.assertIn(key, allowlist)
            self.assertNotEqual(allowlist[key], current_line)


if __name__ == "__main__":
    unittest.main()
