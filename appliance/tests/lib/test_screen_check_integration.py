#!/usr/bin/env python3
"""Integration tests for `screen_contains` / `wait_for_screen_contains`
that need a real `tesseract` binary (so NOT in `test_pure.py`) but do NOT
need a running VM — a `FakeQmp` stands in for `QmpClient`, satisfying only
the one method `screen_contains` actually calls (`screendump(path)`) by
copying a real, pre-existing appliance screenshot to the requested path.
Real OCR, real image files, zero QEMU.

Run with:
    appliance/tests/lib/.venv/bin/python3 -m unittest test_screen_check_integration -v

Skips itself (rather than failing) if `tesseract` isn't on PATH or the
fixture screenshots aren't present, so it degrades gracefully on a machine
that hasn't run this library's setup steps yet.
"""
from __future__ import annotations

import shutil
import tempfile
import time
import unittest
from pathlib import Path

from screen_check import screen_contains, wait_for_screen_contains

REPO_ROOT = Path(__file__).resolve().parents[3]
OOBE_FIXTURE = REPO_ROOT / "appliance" / ".vm" / "s2-evidence" / "a4-firstboot-oobe-on-comp-2026-08-22.png"
DESKTOP_FIXTURE = REPO_ROOT / "appliance" / ".vm" / "d9lock" / "10-home.png"

_TESSERACT_MISSING = shutil.which("tesseract") is None
_FIXTURES_MISSING = not (OOBE_FIXTURE.is_file() and DESKTOP_FIXTURE.is_file())


class FakeQmp:
    """Duck-types just enough of `QmpClient` for `screen_contains`: a
    `screendump(path)` that "takes a screenshot" by copying a fixed real
    PNG to the requested path — so every call sees the exact same, real,
    already-OCR-tuned screenshot. `flips_after` optionally switches which
    fixture is served after N calls, to exercise the boot-wait polling
    path (screen starts blank/wrong, then becomes correct)."""

    def __init__(self, serve: Path, flips_to: Path | None = None, flips_after: int = 0):
        self.serve = serve
        self.flips_to = flips_to
        self.flips_after = flips_after
        self.calls = 0

    def screendump(self, out_path: str, settle: float = 0.0) -> None:
        self.calls += 1
        src = self.flips_to if (self.flips_to and self.calls > self.flips_after) else self.serve
        shutil.copyfile(src, out_path)


@unittest.skipIf(_TESSERACT_MISSING, "tesseract not on PATH")
@unittest.skipIf(_FIXTURES_MISSING, "fixture screenshots not present under appliance/.vm/")
class TestScreenContainsIntegration(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.artifacts_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_finds_real_oobe_text(self) -> None:
        qmp = FakeQmp(OOBE_FIXTURE)
        result = screen_contains("已選擇", qmp, self.artifacts_dir)
        self.assertTrue(result.found)
        self.assertIsNotNone(result.matched_bbox)
        # Sanity-bound the bbox to somewhere plausible on a 1280x800 image,
        # not a runaway match spanning most of the screen (the exact
        # regression this module's find_word_run_bbox fix targets).
        x, y, w, h = result.matched_bbox
        self.assertTrue(0 <= x < 1280 and 0 <= y < 800)
        self.assertLess(w, 200)
        self.assertLess(h, 60)

    def test_finds_real_desktop_text(self) -> None:
        qmp = FakeQmp(DESKTOP_FIXTURE)
        result = screen_contains("DuDuClaw", qmp, self.artifacts_dir)
        self.assertTrue(result.found)

    def test_missing_text_reports_not_found_with_evidence(self) -> None:
        qmp = FakeQmp(DESKTOP_FIXTURE)
        result = screen_contains("這段文字絕對不存在於畫面上", qmp, self.artifacts_dir)
        self.assertFalse(result.found)
        self.assertIsNone(result.matched_bbox)
        self.assertGreater(len(result.evidence_text), 0)  # evidence preserved for a fail() artifact

    def test_wait_for_screen_contains_succeeds_once_text_appears(self) -> None:
        # First call(s) see the OOBE screen (no "DuDuClaw" desktop brand
        # text on it); after 1 call it "boots" to the desktop fixture.
        qmp = FakeQmp(serve=OOBE_FIXTURE, flips_to=DESKTOP_FIXTURE, flips_after=1)
        result = wait_for_screen_contains("DuDuClaw", qmp, self.artifacts_dir, timeout=30.0, interval=0.5)
        self.assertTrue(result.found)
        self.assertGreaterEqual(qmp.calls, 2)  # actually polled more than once

    def test_wait_for_screen_contains_times_out_boundedly(self) -> None:
        qmp = FakeQmp(OOBE_FIXTURE)  # never contains "DuDuClaw" — will never succeed
        start = time.time()
        result = wait_for_screen_contains("DuDuClaw", qmp, self.artifacts_dir, timeout=4.0, interval=1.0)
        elapsed = time.time() - start
        self.assertFalse(result.found)
        # Bounded: must not run away past the timeout by more than one
        # extra poll cycle's worth of OCR work.
        self.assertLess(elapsed, 20.0)


if __name__ == "__main__":
    unittest.main()
