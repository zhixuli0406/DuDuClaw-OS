#!/usr/bin/env python3
"""Exercise the fallback script with real files/bash and fake systemctl/nft.

Run as root on Linux (a disposable container is recommended). No privileges
or network are needed. --platform-root points at the platform checkout whose
sysd owns window.json, so path/schema drift fails instead of being hidden by
a fixture that repeats the shell's assumptions.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "meta-duduclaw/recipes-duduclaw/duduclaw-maint/files/maint-ssh-close"
FIXTURE = Path(__file__).parent / "fixtures/maint-ssh/window.json"
PLATFORM_ROOT = None


class FallbackStateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="maint-close-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data = self.root / "data/system"
        self.keys = self.root / "run/duduclaw-maint-ssh"
        self.state = self.data / "maint-ssh"
        self.state.mkdir(parents=True, mode=0o700)
        self.keys.mkdir(parents=True)
        self.window = self.state / "window.json"
        self.key = self.keys / "authorized_keys"
        self.audit = self.data / "maint-ssh-audit.log"
        self.last_close = self.state / "last-close.json"
        self.port = self.root / "port-open"
        self.port.touch()
        self.fixture = json.loads(FIXTURE.read_text())
        self.fixture_bytes = json.dumps(self.fixture, separators=(",", ":")).encode()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Only OS control commands are substituted. All paths are redirected
        # by prefix, never by replacing WINDOW_FILE or other assignments.
        self.write_stub("systemctl", """#!/bin/sh
case "$1" in
  stop|list-units) exit 0 ;;
  is-active) exit 3 ;;
  *) exit 99 ;;
esac
""")
        self.write_stub("nft", """#!/bin/sh
case "$1 $2" in
  'list set') exit 0 ;;
  'get element') test -f "$TEST_PORT" ;;
  'delete element') rm -f "$TEST_PORT" ;;
  *) exit 99 ;;
esac
""")
        source = SCRIPT.read_text()
        for old, new in [
            ("/data/system", str(self.data)),
            ("/run/duduclaw-maint-ssh", str(self.keys)),
            ("/sys/fs/cgroup/system.slice/system-dropbear.slice/cgroup.kill",
             str(self.root / "absent-cgroup.kill")),
        ]:
            source = source.replace(old, new)
        self.script = self.root / "maint-ssh-close"
        self.script.write_text(source)

    def write_stub(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def write_window(self):
        self.window.write_bytes(self.fixture_bytes)
        self.window.chmod(0o600)

    def close(self):
        result = subprocess.run(
            ["bash", str(self.script)], capture_output=True, text=True,
            env={**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}",
                 "TEST_PORT": str(self.port)}, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.port.exists(), "port 22 must be removed")

    def records(self):
        self.assertTrue(self.audit.is_file(), "a persisted window needs a close audit record")
        return [json.loads(line) for line in self.audit.read_text().splitlines()]

    def test_platform_window_contract(self):
        module = (PLATFORM_ROOT / "crates/duduclaw-sysd/src/maint_ssh/mod.rs").read_text()
        constants = dict(re.findall(r'pub const (\w+): &str = "([^"]+)";', module))
        self.assertEqual(constants["STATE_DIR"], "/data/system/maint-ssh")
        self.assertEqual(constants["KEY_DIR"], "/run/duduclaw-maint-ssh")
        self.assertEqual(constants["WINDOW_FILE"], "window.json")
        fields = re.search(r"pub struct WindowFile \{(.*?)\n\}", module, re.S)
        self.assertIsNotNone(fields)
        names = set(re.findall(r"pub (\w+):", fields.group(1)))
        self.assertEqual(set(self.fixture), names, "fixture must match sysd WindowFile")

    def test_reads_persistent_state_and_preserves_replay_cursor(self):
        self.write_window()
        self.key.write_text("test key removed without parsing\n")
        # A stale tmpfs file must never override the actual persisted window.
        (self.keys / "window.json").write_text('{"window_id":"wrong-tmpfs-window"}')
        self.close()
        self.assertFalse(self.key.exists())
        self.assertEqual(self.window.read_bytes(), self.fixture_bytes)
        record, = self.records()
        self.assertEqual(record["window_id"], self.fixture["window_id"])
        self.assertEqual(record["removed_fingerprint"], self.fixture["key_fingerprint"])
        for field in ["last_cursor", "logins_recorded", "logins_over_cap",
                      "logouts_recorded", "logouts_over_cap", "auth_failures"]:
            self.assertEqual(record[field], self.fixture[field], field)
        self.assertEqual(record["trigger"], "fallback_timer")
        self.assertFalse(record["events_complete"])
        self.assertIsNone(record["auth_failure_sources"])
        self.assertEqual(record["problems"], [])
        last = json.loads(self.last_close.read_text())
        self.assertEqual(last["window_id"], self.fixture["window_id"])
        self.assertFalse(last["events_complete"])
        self.assertFalse(last["events_lost"])
        for path in [self.audit, Path(f"{self.audit}.lock"), self.last_close, self.window]:
            self.assertEqual(path.stat().st_mode & 0o777, 0o600, str(path))

    def test_persistent_window_without_key_still_records_close(self):
        # After a reboot / an earlier fallback the tmpfs key may be gone,
        # but sysd still needs the persisted state for journal replay.
        self.write_window()
        self.close()
        record, = self.records()
        self.assertEqual(record["window_id"], self.fixture["window_id"])
        self.assertEqual(self.window.read_bytes(), self.fixture_bytes)

    def test_no_window_does_not_create_audit_or_replace_last_close(self):
        # An unrelated stale tmpfs JSON file is not a sysd window.
        (self.keys / "window.json").write_text('{"window_id":"stale-tmpfs"}')
        self.last_close.write_text('{"previous":"kept"}\n')
        before = self.last_close.read_bytes()
        self.close()
        self.assertFalse(self.audit.exists())
        self.assertFalse(Path(f"{self.audit}.lock").exists())
        self.assertEqual(self.last_close.read_bytes(), before)
        self.assertFalse(self.window.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform-root", required=True, type=Path)
    args = parser.parse_args()
    if sys.platform != "linux" or os.geteuid() != 0:
        parser.error("run as root inside a disposable Linux container")
    PLATFORM_ROOT = args.platform_root.resolve()
    unittest.main(argv=[sys.argv[0]], verbosity=2)
