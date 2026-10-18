#!/usr/bin/env python3
"""Run the real image payload check against isolated ELF-shaped fixtures."""
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / 'meta-duduclaw/recipes-core/images/duduclaw-image-local-model.inc'
FILES = {'/usr/bin/llama-server': 0o755, '/usr/bin/llama-cli': 0o755,
         '/usr/libexec/duduclaw/llama-server-run': 0o755,
         '/usr/lib/systemd/system/duduclaw-llama-server.service': 0o644}

class BB:
    @staticmethod
    def fatal(message):
        raise RuntimeError(message)

class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.uid = self.gid = 0
        self.mode_override = None
        match = re.search(r'^python duduclaw_check_local_model \(\) \{\n(.*?)^\}', CHECK.read_text(), re.M | re.S)
        self.assertIsNotNone(match)
        self.code = compile(textwrap.dedent(match.group(1)), str(CHECK), 'exec')
        for name, mode in FILES.items():
            f = self.path(name)
            f.parent.mkdir(parents=True, exist_ok=True)
            if name.startswith('/usr/bin/'):
                data = bytearray(64)
                data[:7] = b'\x7fELF\x02\x01\x01'
                struct.pack_into('<HHI', data, 16, 3, 62, 1)
                f.write_bytes(data)
            else:
                f.write_text('# isolated payload fixture\n')
            f.chmod(mode)

    def path(self, name):
        return self.root / name.lstrip('/')

    def check(self):
        lstat, fstat = os.lstat, os.fstat
        def owner(st):
            fields = list(st)
            fields[4:6] = [self.uid, self.gid]
            if self.mode_override and st.st_ino == self.mode_override[0]:
                fields[0] = (fields[0] & ~0o7777) | self.mode_override[1]
            return os.stat_result(fields)
        class Data:
            def getVar(_, name):
                return {'IMAGE_ROOTFS': str(self.root), 'bindir': '/usr/bin',
                        'libexecdir': '/usr/libexec',
                        'systemd_system_unitdir': '/usr/lib/systemd/system'}[name]
        with patch('os.lstat', side_effect=lambda *a, **k: owner(lstat(*a, **k))), \
             patch('os.fstat', side_effect=lambda *a, **k: owner(fstat(*a, **k))):
            exec(self.code, {'d': Data(), 'bb': BB})

    def test_complete_model_payload(self):
        self.check()

    def test_missing_engine_service_or_wrapper_blocks_image(self):
        for name in FILES:
            with self.subTest(name=name):
                f = self.path(name); original = f.read_bytes(); mode = f.stat().st_mode
                f.unlink()
                with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()
                f.write_bytes(original); f.chmod(stat.S_IMODE(mode))

    def test_payload_modes_are_exact_and_not_setuid(self):
        for name, correct in FILES.items():
            with self.subTest(name=name):
                f = self.path(name); f.chmod(0o600)
                with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()
                f.chmod(correct)

    def test_setuid_metadata_is_rejected_under_pseudo(self):
        # The sandbox may strip real setuid fixture bits; pseudo supplies metadata only.
        f = self.path('/usr/bin/llama-server')
        self.mode_override = (f.stat().st_ino, 0o4755)
        with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_uid_and_gid_must_be_root(self):
        for uid, gid in [(1000, 0), (0, 1000)]:
            with self.subTest(uid=uid, gid=gid):
                self.uid, self.gid = uid, gid
                with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_symlink_leaf_is_not_a_payload(self):
        f = self.path('/usr/bin/llama-server'); target = self.root / 'other'
        f.rename(target); f.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_symlink_parent_is_not_followed(self):
        f = self.path('/usr/bin'); target = self.root / 'elsewhere'
        f.rename(target); f.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_empty_config_files_are_rejected(self):
        self.path('/usr/libexec/duduclaw/llama-server-run').write_bytes(b'')
        with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_wrong_architecture_or_truncated_engine_is_rejected(self):
        f = self.path('/usr/bin/llama-server'); original = f.read_bytes()
        for data in [b'script', original[:30], original[:18] + b'\xb7\x00' + original[20:]]:
            with self.subTest(data_length=len(data)):
                f.write_bytes(data)
                with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_replacement_between_lstat_and_open_is_rejected(self):
        original_open = os.open
        target = self.path('/usr/bin/llama-server')
        def replace_then_open(path, flags, *args, **kwargs):
            replacement = target.with_name('replacement')
            replacement.write_bytes(target.read_bytes())
            replacement.chmod(0o755)
            os.replace(replacement, target)
            return original_open(path, flags, *args, **kwargs)
        with patch('os.open', side_effect=replace_then_open):
            with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_change_during_read_is_rejected(self):
        original_fstat = os.fstat
        calls = 0
        def change_on_second_stat(fd):
            nonlocal calls
            calls += 1
            if calls == 2:
                with self.path('/usr/bin/llama-server').open('ab') as writer:
                    writer.write(b'changed')
            return original_fstat(fd)
        with patch('os.fstat', side_effect=change_on_second_stat):
            with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_path_replacement_after_open_is_rejected(self):
        original_fstat = os.fstat
        target = self.path('/usr/bin/llama-server')
        calls = 0
        def replace_on_second_stat(fd):
            nonlocal calls
            calls += 1
            if calls == 2:
                replacement = target.with_name('new-payload')
                replacement.write_bytes(b'WRONG_NOT_ELF_PAYLOAD')
                replacement.chmod(0o755)
                os.replace(replacement, target)
            return original_fstat(fd)
        with patch('os.fstat', side_effect=replace_on_second_stat):
            with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

    def test_fifo_replacement_cannot_block_or_pass(self):
        child = r"""
import os,runpy,re,textwrap,sys
from pathlib import Path
from unittest.mock import patch
ns=runpy.run_path(sys.argv[1],run_name='child_fixture')
case=ns['PayloadTests']();case.root=Path(sys.argv[2]);case.uid=case.gid=0;case.mode_override=None
body=re.search(r'^python duduclaw_check_local_model \(\) \{\n(.*?)^\}',ns['CHECK'].read_text(),re.M|re.S).group(1)
case.code=compile(textwrap.dedent(body),str(ns['CHECK']),'exec')
target=case.path('/usr/bin/llama-server');original=os.open
def replace_fifo(path,flags,*args,**kwargs):
 target.unlink();os.mkfifo(target,0o600)
 return original(path,flags,*args,**kwargs)
with patch('os.open',side_effect=replace_fifo):
 try:case.check()
 except RuntimeError as error:
  assert 'local model' in str(error);print('FIFO_REPLACEMENT_REJECTED');raise SystemExit(0)
raise SystemExit(3)
"""
        result = subprocess.run([sys.executable, '-c', child, __file__, str(self.root)],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('FIFO_REPLACEMENT_REJECTED', result.stdout)

    def test_failed_payload_open_is_not_a_pass(self):
        with patch('os.open', side_effect=PermissionError('fixture denied')):
            with self.assertRaisesRegex(RuntimeError, 'local.model'): self.check()

if __name__ == '__main__':
    unittest.main()
