#!/usr/bin/env python3
"""Dependency-free unit tests for the pure logic in this library — no
`tesseract` binary, no QEMU, no Pillow needed for THIS file specifically
(though `ocr.py` still imports Pillow at module load time, so this still
has to run under the project venv). Run with:

    appliance/tests/lib/.venv/bin/python3 -m unittest test_pure -v

Covers the two correctness bugs actually found and fixed while building
this library against real screenshots (see `ocr.py`'s `find_word_run_bbox`
doc for the full story) — these tests exist specifically so neither
regresses silently.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ocr import Word, find_word_run_bbox, normalize_nospace, normalize_text, text_found
from screen_check import _parse_geometry_reply, _py_json_dumps_shell_safe
from test_run import TestRun


def word(text: str, x: int, y: int, w: int, h: int, line_key=(1, 1, 1)) -> Word:
    return Word(text=text, x=x, y=y, w=w, h=h, conf=95.0, line_key=line_key)


class TestNormalize(unittest.TestCase):
    def test_casefold(self) -> None:
        self.assertEqual(normalize_text("English"), normalize_text("ENGLISH"))

    def test_fullwidth_halfwidth(self) -> None:
        # NFKC folds fullwidth ASCII (U+FF21 'Ａ' etc.) to plain ASCII.
        self.assertEqual(normalize_text("ＡＢＣ"), normalize_text("ABC"))

    def test_whitespace_collapsed(self) -> None:
        self.assertEqual(normalize_text("a   b\tc"), "a b c")

    def test_nospace_strips_all_whitespace(self) -> None:
        self.assertEqual(normalize_nospace("已 選 擇"), normalize_nospace("已選擇"))


class TestTextFound(unittest.TestCase):
    def test_exact_substring(self) -> None:
        self.assertTrue(text_found("hello world", "world"))

    def test_case_insensitive(self) -> None:
        self.assertTrue(text_found("Choose your Language", "choose your language"))

    def test_cjk_word_split_by_ocr(self) -> None:
        # Tesseract sometimes inserts a space between CJK glyphs a human
        # reads as one word/line — text_found must tolerate that.
        self.assertTrue(text_found("已 選擇", "已選擇"))
        self.assertTrue(text_found("已選 擇", "已選擇"))

    def test_not_found(self) -> None:
        self.assertFalse(text_found("hello world", "goodbye"))

    def test_empty_needle_never_matches(self) -> None:
        self.assertFalse(text_found("hello world", ""))
        self.assertFalse(text_found("hello world", "   "))


class TestFindWordRunBbox(unittest.TestCase):
    def test_single_word_match(self) -> None:
        words = [word("English", 100, 200, 50, 20)]
        self.assertEqual(find_word_run_bbox(words, "English"), (100, 200, 50, 20))

    def test_multi_word_run_union_bbox(self) -> None:
        words = [word("已", 100, 200, 10, 20), word("選擇", 110, 202, 30, 18)]
        self.assertEqual(find_word_run_bbox(words, "已選擇"), (100, 200, 40, 20))

    def test_never_crosses_a_line_boundary(self) -> None:
        # Regression test for bug #1 (see ocr.py's find_word_run_bbox doc):
        # words from two different lines must never be glued into one run
        # even if their concatenation happens to contain the needle.
        words = [
            word("已", 100, 200, 10, 20, line_key=(1, 1, 1)),
            word("選擇", 500, 600, 30, 18, line_key=(2, 1, 1)),  # different line
        ]
        self.assertIsNone(find_word_run_bbox(words, "已選擇"))

    def test_picks_tightest_run_not_first_superset_match(self) -> None:
        # Regression test for bug #2: a line reading "繁體中文已選擇" (one
        # OCR line containing a label AND a trailing status tag) must
        # return the bbox of JUST "已選擇", not the whole line, even though
        # the whole-line concatenation also technically contains "已選擇"
        # as a substring.
        words = [
            word("繁體", 400, 400, 50, 20),
            word("中文", 450, 400, 50, 20),
            word("已", 960, 405, 15, 12),
            word("選擇", 975, 405, 25, 12),
        ]
        self.assertEqual(find_word_run_bbox(words, "已選擇"), (960, 405, 40, 12))

    def test_no_match_returns_none(self) -> None:
        words = [word("hello", 0, 0, 10, 10)]
        self.assertIsNone(find_word_run_bbox(words, "goodbye"))


class FakeConsole:
    """Duck-types just enough of `SerialConsole` for `assert_no_failed_units`:
    a `run(command, timeout=...)` that returns a canned string regardless of
    the command, so the parsing/exempt-filtering logic is testable without a
    real serial connection."""

    def __init__(self, canned_output: str):
        self.canned_output = canned_output

    def run(self, command: str, timeout: float = 30.0) -> str:
        return self.canned_output


class TestAssertNoFailedUnits(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.run_obj = TestRun(name="unittest-failed-units", artifacts_root=Path(self._tmp.name))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_clean_output_passes_with_empty_list(self) -> None:
        console = FakeConsole("")
        result = self.run_obj.assert_no_failed_units(console, exempt=[])
        self.assertEqual(result, [])

    def test_failed_unit_not_exempted_raises_test_failure(self) -> None:
        from test_run import TestFailure

        console = FakeConsole("● some-broken.service loaded failed failed Some Broken Service\n")
        with self.assertRaises(TestFailure) as cm:
            self.run_obj.assert_no_failed_units(console, exempt=[])
        self.assertIn("some-broken.service", cm.exception.reason)
        # fail() with qmp=None must still write the evidence .txt (raw
        # `systemctl --failed` output) even with no screenshot to take.
        self.assertIsNotNone(cm.exception.evidence_path)
        self.assertIsNone(cm.exception.screenshot_path)

    def test_exempted_unit_does_not_raise(self) -> None:
        console = FakeConsole("● serial-getty@ttyAMA0.service loaded failed failed Serial Getty\n")
        result = self.run_obj.assert_no_failed_units(console, exempt=[r"serial-getty@ttyAMA0\.service"])
        self.assertEqual(result, ["serial-getty@ttyAMA0.service"])  # still reported, just not fatal

    def test_mix_of_exempt_and_non_exempt_raises_on_the_non_exempt_one(self) -> None:
        console = FakeConsole(
            "● serial-getty@ttyAMA0.service loaded failed failed Serial Getty\n"
            "● real-problem.service loaded failed failed Real Problem\n"
        )
        from test_run import TestFailure

        with self.assertRaises(TestFailure) as cm:
            self.run_obj.assert_no_failed_units(console, exempt=[r"serial-getty@ttyAMA0\.service"])
        self.assertIn("real-problem.service", cm.exception.reason)
        self.assertNotIn("serial-getty", cm.exception.reason)


class TestRunArtifactNaming(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.run = TestRun(name="unittest-probe", artifacts_root=Path(self._tmp.name))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_run_dir_created(self) -> None:
        self.assertTrue(self.run.run_dir.is_dir())
        self.assertIn("unittest-probe", self.run.run_dir.name)

    def test_repeated_step_name_gets_suffixed_not_overwritten(self) -> None:
        p1 = self.run._step_path("success", "desktop", "png")
        p2 = self.run._step_path("success", "desktop", "png")
        p3 = self.run._step_path("success", "desktop", "png")
        self.assertEqual(p1.name, "success-desktop.png")
        self.assertEqual(p2.name, "success-desktop-2.png")
        self.assertEqual(p3.name, "success-desktop-3.png")
        self.assertEqual(len({p1, p2, p3}), 3)


class TestGeometryReplyParsing(unittest.TestCase):
    """`query_window_geometry`'s guest-side snippet round-trips through a
    live serial console (not exercised here — no VM), but the reply
    parsing itself is pure and worth locking down independently."""

    def test_clean_json_reply(self) -> None:
        r = _parse_geometry_reply('{"ok": true, "window": {"origin_x": 10, "origin_y": 20}}')
        self.assertTrue(r.ok)
        self.assertEqual(r.raw["window"]["origin_x"], 10)

    def test_json_with_shell_echo_noise_before_it(self) -> None:
        out = "M12345678-B\n{\"ok\": true, \"window\": {\"origin_x\": 1}}\nM12345678-E"
        r = _parse_geometry_reply(out)
        self.assertTrue(r.ok)
        self.assertEqual(r.raw["window"]["origin_x"], 1)

    def test_error_reply(self) -> None:
        r = _parse_geometry_reply('{"ok": false, "error": "window_not_found"}')
        self.assertTrue(r.ok)  # ok=True means "we parsed a reply", not "comp found the window"
        self.assertEqual(r.raw["error"], "window_not_found")

    def test_no_json_at_all(self) -> None:
        r = _parse_geometry_reply("[serial_console: TIMEOUT after 10.0s]")
        self.assertFalse(r.ok)
        self.assertIn("no JSON reply", r.error)

    def test_malformed_json(self) -> None:
        r = _parse_geometry_reply("{not valid json")
        self.assertFalse(r.ok)
        self.assertIn("bad JSON", r.error)


class TestShellSafeDictRepr(unittest.TestCase):
    def test_round_trips_through_python_eval(self) -> None:
        obj = {"op": "window_geometry", "pid": 1234, "app_id": "org.gnome.TextEditor"}
        rendered = _py_json_dumps_shell_safe(obj)
        # Must be a valid Python literal (embedded directly into a `-c`
        # snippet as source code, not passed through json.loads).
        self.assertEqual(eval(rendered), obj)  # noqa: S307 - trusted, test-local literal

    def test_uses_single_quotes_not_double(self) -> None:
        # The snippet embeds this inside a double-quoted `-c "..."` shell
        # argument — a double quote in the rendered literal would break out
        # of it.
        rendered = _py_json_dumps_shell_safe({"app_id": "foo"})
        self.assertNotIn('"', rendered)


if __name__ == "__main__":
    unittest.main()
