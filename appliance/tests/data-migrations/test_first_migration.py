#!/usr/bin/env python3
"""Host-side functional test for the first H3g /data migration (H3g).

Runs the REAL shipped script — `appliance/mkosi.extra/usr/share/duduclaw/
migrations/1787540626.sh` — directly against a fake `$DUDUCLAW_HOME`, exactly
per the testing discipline borrowed from omarchy's own
`agents/skills/migrations.md` (cited in `research/native-os-2026-08/
omarchy-borrowings-2026-08.md` §2.3): build an "old" fixture state, run the
script, run it a second time to prove idempotency, then run it against a
"not old" fixture to prove it does not clobber state that is already
correct. No VM, no root, no image — runs anywhere bash + python3 exist.

This tests the SCRIPT's own idempotency and correctness. The generic
runner mechanics (marker files, stop-at-first-failure, ordering) are
covered separately as Rust unit tests in
`crates/duduclaw-core/src/data_migrations.rs`.

Usage:  python3 appliance/tests/data-migrations/test_first_migration.py
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCRIPT = (
    REPO_ROOT
    / "appliance/mkosi.extra/usr/share/duduclaw/migrations/1787540626.sh"
)

PASS = []
FAIL = []


def check(name, cond, detail=""):
    if cond:
        PASS.append(name)
        print(f"  PASS  {name}")
    else:
        FAIL.append(name)
        print(f"  FAIL  {name}  {detail}")


def mode_of(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def run_script(home: Path):
    env = dict(os.environ)
    env["DUDUCLAW_HOME"] = str(home)
    proc = subprocess.run(
        ["bash", "-euo", "pipefail", str(SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
    )
    return proc


def scenario_old_state_then_idempotent_rerun():
    print("\n[scenario] old state (system/ at 0755, mkdir -p default) -> migrate -> rerun")
    with tempfile.TemporaryDirectory() as td:
        home = Path(td) / "duduclaw"
        system_dir = home / "system"
        system_dir.mkdir(parents=True)
        system_dir.chmod(0o755)  # the pre-fix mkdir -p default
        (system_dir / "device.key").write_text("fake-secret\n")
        (system_dir / "device.key").chmod(0o600)
        (system_dir / "machine-id").write_text("deadbeef" * 4 + "\n")

        before = mode_of(system_dir)
        check("fixture starts at 0755 (pre-migration state)", before == 0o755, f"got {oct(before)}")

        first = run_script(home)
        check("first run exits 0", first.returncode == 0, first.stderr)
        check(
            "first run echoes what it is doing",
            "tightening" in first.stdout and str(system_dir) in first.stdout,
            first.stdout,
        )
        after_first = mode_of(system_dir)
        check("system/ is 0700 after first run", after_first == 0o700, f"got {oct(after_first)}")
        check(
            "device.key content untouched by the migration",
            (system_dir / "device.key").read_text() == "fake-secret\n",
        )
        check(
            "device.key mode untouched (still 0600)",
            mode_of(system_dir / "device.key") == 0o600,
        )

        second = run_script(home)
        check("second run (idempotent replay) exits 0", second.returncode == 0, second.stderr)
        after_second = mode_of(system_dir)
        check(
            "system/ still 0700 after second run (idempotent, no drift)",
            after_second == 0o700,
            f"got {oct(after_second)}",
        )


def scenario_already_correct_state_is_a_true_no_op():
    print("\n[scenario] already-0700 state (fresh install / already migrated) -> migrate")
    # Directory permissions have no user-adjustable "customization" axis in
    # this dashboard (nothing in the UI lets an operator choose a different
    # mode for $DUDUCLAW_HOME/system), so the closest analogue to omarchy's
    # "does not touch the user's own customization" test is: running against
    # a state that is ALREADY at the migration's target must be a true
    # no-op — no error, no unnecessary write, same end state.
    with tempfile.TemporaryDirectory() as td:
        home = Path(td) / "duduclaw"
        system_dir = home / "system"
        system_dir.mkdir(parents=True)
        system_dir.chmod(0o700)  # already correct — e.g. corrected firstboot-provision.sh
        (system_dir / "device.key").write_text("fake-secret\n")
        (system_dir / "device.key").chmod(0o600)

        result = run_script(home)
        check("run against already-correct state exits 0", result.returncode == 0, result.stderr)
        check(
            "system/ remains 0700 (no-op, not just idempotent-after-a-change)",
            mode_of(system_dir) == 0o700,
        )
        check(
            "device.key untouched",
            (system_dir / "device.key").read_text() == "fake-secret\n",
        )


def scenario_missing_system_dir_is_a_graceful_no_op():
    print("\n[scenario] system/ does not exist yet -> migrate")
    with tempfile.TemporaryDirectory() as td:
        home = Path(td) / "duduclaw"
        home.mkdir(parents=True)
        # deliberately do NOT create home/system

        result = run_script(home)
        check(
            "run against a home with no system/ still exits 0 (not this script's job to create it)",
            result.returncode == 0,
            result.stderr,
        )
        check(
            "script logs that there was nothing to do",
            "does not exist yet" in result.stdout,
            result.stdout,
        )
        check("system/ was NOT created by this migration", not (home / "system").exists())


def scenario_no_shebang_and_mode_0644():
    print("\n[scenario] shipped file itself matches the H3g script contract")
    check("script file exists", SCRIPT.is_file(), str(SCRIPT))
    if not SCRIPT.is_file():
        return
    raw = SCRIPT.read_bytes()
    first_line = raw.split(b"\n", 1)[0]
    check("no shebang on the first line", not first_line.startswith(b"#!"), first_line)
    mode = mode_of(SCRIPT)
    check("file mode is 0644 as shipped in the repo", mode == 0o644, oct(mode))


def main():
    if not SCRIPT.is_file():
        print(f"FATAL: migration script not found at {SCRIPT}")
        return 2
    if shutil.which("bash") is None:
        print("FATAL: bash not found on PATH")
        return 2

    scenario_no_shebang_and_mode_0644()
    scenario_old_state_then_idempotent_rerun()
    scenario_already_correct_state_is_a_true_no_op()
    scenario_missing_system_dir_is_a_graceful_no_op()

    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
