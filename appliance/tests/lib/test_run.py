#!/usr/bin/env python3
"""`TestRun` — the artifact/failure convention piece of the Q3-OCR helper
library: one run directory per test invocation under
`appliance/.vm/test-artifacts/<run-ts>-<name>/`, `fail()` always takes a
screenshot before raising, `success(step)` snapshots each distinct state a
happy-path test passes through as `success-<step>.png`, and
`assert_no_failed_units` is the "no failed systemd unit" acceptance check
run over the serial console.

`appliance/.vm/` is gitignored (`appliance/.gitignore`'s `.vm/` rule) — this
is deliberately consistent with every other piece of VM run-state
(disk images, vars files, prior ad-hoc evidence screenshots already living
under `appliance/.vm/*-evidence/`), not a new convention.
"""
from __future__ import annotations

import re
import time
from dataclasses import dataclass, field
from pathlib import Path

from qmp_client import QmpClient
from serial_console import SerialConsole

REPO_ROOT = Path(__file__).resolve().parents[3]  # appliance/tests/lib/.. .. ..
DEFAULT_ARTIFACTS_ROOT = REPO_ROOT / "appliance" / ".vm" / "test-artifacts"


class TestFailure(RuntimeError):
    """Raised by `TestRun.fail()`. Carries the artifact paths so a caller's
    `except TestFailure as e:` can report them without re-deriving the run's
    file-naming scheme."""

    def __init__(self, reason: str, screenshot_path: str | None, evidence_path: str | None):
        super().__init__(reason)
        self.reason = reason
        self.screenshot_path = screenshot_path
        self.evidence_path = evidence_path


@dataclass
class TestRun:
    name: str
    artifacts_root: Path = field(default_factory=lambda: DEFAULT_ARTIFACTS_ROOT)
    run_dir: Path = field(init=False)
    _step_counts: dict[str, int] = field(default_factory=dict, init=False)

    def __post_init__(self) -> None:
        ts = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        self.run_dir = self.artifacts_root / f"{ts}-{self.name}"
        self.run_dir.mkdir(parents=True, exist_ok=True)

    def _step_path(self, prefix: str, step: str, ext: str) -> Path:
        """`<prefix>-<step>.<ext>`, de-duplicated with a `-2`, `-3`, ...
        suffix if the same step name is recorded more than once in one run
        (e.g. a retried boot-wait poll) — never silently overwrites an
        earlier artifact."""
        key = f"{prefix}-{step}"
        n = self._step_counts.get(key, 0) + 1
        self._step_counts[key] = n
        suffix = "" if n == 1 else f"-{n}"
        return self.run_dir / f"{prefix}-{step}{suffix}.{ext}"

    def success(self, step: str, qmp: QmpClient) -> str:
        """Screenshot the current state as `success-<step>.png`. Call this
        at every distinct state a happy-path flow passes through (module
        doc's "each relevant, distinct state" convention), not just at the
        very end — a run that fails at step 5 should still show what steps
        1-4 actually looked like."""
        path = self._step_path("success", step, "png")
        qmp.screendump(str(path))
        return str(path)

    def fail(
        self,
        step: str,
        reason: str,
        qmp: QmpClient | None = None,
        ocr_evidence: str | None = None,
    ) -> None:
        """Always takes a screenshot (when `qmp` is given) before raising —
        the module doc's "fail() 自動截圖" requirement. `ocr_evidence`
        (typically `ScreenCheckResult.evidence_text`) is written alongside
        as a `.txt` so a human reviewing the failure sees exactly what OCR
        recognized, not just that it didn't match."""
        screenshot_path: str | None = None
        if qmp is not None:
            screenshot_path = str(self._step_path("fail", step, "png"))
            qmp.screendump(screenshot_path)
        evidence_path: str | None = None
        if ocr_evidence is not None:
            evidence_path = str(self._step_path("fail", step, "txt"))
            Path(evidence_path).write_text(
                f"step: {step}\nreason: {reason}\ntimestamp: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n\n{ocr_evidence}",
                encoding="utf-8",
            )
        raise TestFailure(reason, screenshot_path, evidence_path)

    def assert_no_failed_units(
        self,
        console: SerialConsole,
        exempt: list[str] = (),
        step: str = "failed-units",
        qmp: QmpClient | None = None,
    ) -> list[str]:
        """Runs `systemctl --failed --no-legend` over `console` and fails
        (via `self.fail`) if any unit is failed and not matched by one of
        `exempt`'s regexes (`re.fullmatch` against the unit name — e.g.
        `serial-getty@ttyAMA0.service` is a debug-only convenience this
        project's own working disks add on purpose, see
        `serial_console.py`'s module doc, and may need exempting on a disk
        that was booted without a real console attached).

        Returns the list of failed unit names on success (empty list = a
        genuinely clean `systemctl --failed`)."""
        out = console.run("systemctl --failed --no-legend", timeout=15.0)
        failed_units: list[str] = []
        for line in out.splitlines():
            line = line.strip()
            if not line or line.startswith("[serial_console:"):
                continue
            # `systemctl --failed` prefixes each row with a "●" status dot
            # (UNIT is the SECOND whitespace-separated column, not the
            # first — found by a unit test with canned output; taking
            # column 0 silently collected "●" as every "unit name" and let
            # every real failure slip past the `exempt` regex match).
            if line.startswith("●"):
                line = line[1:].strip()
            if not line:
                continue
            unit = line.split()[0]
            failed_units.append(unit)
        unexempted = [u for u in failed_units if not any(re.fullmatch(pat, u) for pat in exempt)]
        if unexempted:
            reason = f"failed systemd units: {', '.join(unexempted)}"
            self.fail(step, reason, qmp=qmp, ocr_evidence=f"raw `systemctl --failed --no-legend` output:\n{out}")
        return failed_units
