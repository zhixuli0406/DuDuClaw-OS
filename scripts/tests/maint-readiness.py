#!/usr/bin/env python3
"""Exercise the actual rootfs readiness check without BitBake or compilation.

The fixture uses tiny ELF-shaped stand-ins, never production binaries. Only
fixture ownership is replaced with pseudo's root ownership on non-root hosts.
"""
import os
import pathlib
import re
import stat
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKS = ROOT / 'meta-duduclaw/recipes-core/images/duduclaw-maint-checks.inc'

class FakeData:
    def __init__(self, root):
        self.values = {
            'IMAGE_ROOTFS': str(root), 'DUDUCLAW_MAINT_READY': '/usr/lib/duduclaw/maint-ssh.ready',
            'DUDUCLAW_MAINT_TOOLS': '/usr/libexec/duduclaw/maint-shell /usr/libexec/duduclaw/maint-helper',
            'bindir': '/usr/bin', 'systemd_system_unitdir': '/usr/lib/systemd/system',
            'libexecdir': '/usr/libexec',
            'DUDUCLAW_MAINT_SHELL': '/usr/libexec/duduclaw/maint-shell',
            'DUDUCLAW_MAINT_CLOSE': '/usr/libexec/duduclaw/maint-ssh-close',
        }
    def getVar(self, name):
        return self.values[name]

class FakeBB:
    @staticmethod
    def fatal(message):
        raise RuntimeError(message)

class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        match = re.search(r'^python duduclaw_check_maint_ready \(\) \{\n(.*?)^\}', CHECKS.read_text(), re.M | re.S)
        self.assertIsNotNone(match, 'the final readiness check must exist')
        self.code = compile(textwrap.dedent(match.group(1)), str(CHECKS), 'exec')
        self.owner_uid = 0
        self.data = FakeData(self.root)
        self.write('/usr/lib/duduclaw/maint-ssh.ready', b'1\n', 0o644)
        for tool in self.data.getVar('DUDUCLAW_MAINT_TOOLS').split():
            self.write(tool, b'\x7fELFfixture', 0o700 if tool.endswith('maint-helper') else 0o755)
        self.write('/usr/libexec/duduclaw/maint-ssh-close', b'#!/bin/bash\n', 0o700)
        self.write('/usr/bin/duduclaw', b'\x7fELFfixture ssh_public_key', 0o755)
        self.write('/usr/bin/duduclaw-sysd', b'\x7fELFfixture ssh_maint_open ssh_maint_status', 0o755)

    def write(self, path, content, mode):
        target = self.root / path.lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        target.chmod(mode)
        return target

    def run_check(self):
        original = os.lstat
        def pseudo_lstat(path, *args, **kwargs):
            result = original(path, *args, **kwargs)
            if str(path).startswith(str(self.root)):
                values = list(result); values[4] = self.owner_uid; values[5] = 0
                return os.stat_result(values)
            return result
        with patch('os.lstat', side_effect=pseudo_lstat):
            exec(self.code, {'d': self.data, 'bb': FakeBB})

    def test_complete_fixture_passes(self):
        self.run_check()

    def test_exact_contract_modes_are_required(self):
        cases = [
            ('/usr/libexec/duduclaw/maint-shell', 0o700, 0o755),
            ('/usr/libexec/duduclaw/maint-helper', 0o755, 0o700),
            ('/usr/libexec/duduclaw/maint-ssh-close', 0o755, 0o700),
            ('/usr/lib/duduclaw/maint-ssh.ready', 0o600, 0o644),
            ('/usr/libexec/duduclaw/maint-shell', 0o4755, 0o755),
            ('/usr/libexec/duduclaw/maint-helper', 0o4700, 0o700),
            ('/usr/libexec/duduclaw/maint-ssh-close', 0o6700, 0o700),
        ]
        for path, wrong, correct in cases:
            with self.subTest(path=path, mode=oct(wrong)):
                target = self.root / path.lstrip('/')
                target.chmod(wrong)
                try:
                    with self.assertRaisesRegex(RuntimeError, 'mode'):
                        self.run_check()
                finally:
                    target.chmod(correct)
        self.run_check()

    def test_nonroot_ownership_is_refused(self):
        self.owner_uid = 1000
        with self.assertRaisesRegex(RuntimeError, 'root:root'): self.run_check()

    def test_missing_or_bad_marker_is_refused(self):
        for content in [b'', b'0\n', b'1\nextra']:
            with self.subTest(content=content):
                self.write('/usr/lib/duduclaw/maint-ssh.ready', content, 0o644)
                with self.assertRaisesRegex(RuntimeError, 'marker'):
                    self.run_check()
        (self.root / 'usr/lib/duduclaw/maint-ssh.ready').unlink()
        with self.assertRaises(RuntimeError): self.run_check()

    def test_missing_menu_or_old_sysd_is_refused(self):
        shell = self.root / 'usr/libexec/duduclaw/maint-shell'
        shell.unlink()
        with self.assertRaisesRegex(RuntimeError, 'maint-shell'): self.run_check()
        self.write('/usr/libexec/duduclaw/maint-shell', b'\x7fELFfixture', 0o755)
        self.write('/usr/bin/duduclaw-sysd', b'\x7fELFold', 0o755)
        with self.assertRaisesRegex(RuntimeError, 'ssh_maint_open'): self.run_check()

    def test_symlink_or_writable_tool_is_refused(self):
        helper = self.root / 'usr/libexec/duduclaw/maint-helper'
        helper.chmod(0o777)
        with self.assertRaisesRegex(RuntimeError, 'maint-helper'): self.run_check()
        helper.unlink(); helper.symlink_to('maint-shell')
        with self.assertRaisesRegex(RuntimeError, 'maint-helper'): self.run_check()

    def test_baked_authorized_keys_is_refused_even_as_symlink(self):
        key = self.write('/root/.ssh/authorized_keys', b'', 0o600)
        with self.assertRaisesRegex(RuntimeError, 'authorized_keys'): self.run_check()
        key.unlink(); key.symlink_to('/missing')
        with self.assertRaisesRegex(RuntimeError, 'authorized_keys'): self.run_check()

if __name__ == '__main__': unittest.main()
