#!/usr/bin/env python3
"""Run the shipped installer's real write/post-write section on regular files.

No root, block devices, VM, decompression staging file or third-party modules.
Only external tools are replaced: successful streams preserve arbitrary bytes;
zstd/pv/dd can fail after delivering a prefix. The script text and shell options
are read from the production source, so dropping pipefail makes these tests red.
"""
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "meta-duduclaw/recipes-duduclaw/duduclaw-os-installer/files/duduclaw-os-install.sh"
PAYLOAD = bytes(range(256)) * 4097
STUB = r'''
import os, pathlib, sys, time
tool = pathlib.Path(sys.argv[0]).name
failure = os.environ.get('FAIL_STAGE', '')
with open(os.environ['TRACE'], 'a') as log:
    log.write('%s %s\n' % (tool, os.getpid()))
if tool == 'zstd' and '-lv' in sys.argv:
    if failure == 'listing':
        sys.exit(42)
    print('Decompressed Size: 1 MiB (%s B)' % len(pathlib.Path(os.environ['IMG']).read_bytes()))
    sys.exit(0)
if tool == 'dd' and os.environ.get('STARTUP_READY'):
    pathlib.Path(os.environ['STARTUP_READY']).touch()
if tool == 'zstd':
    if os.environ.get('SLOW_STREAM') == '1':
        time.sleep(30)
    data = pathlib.Path(os.environ['IMG']).read_bytes()
elif tool in ('pv', 'dd'):
    data = sys.stdin.buffer.read()
else:
    sys.exit(42 if tool == failure else 0)
if tool == failure:
    data = data[:len(data)//3]
if tool == 'dd':
    target = next(arg[3:] for arg in sys.argv[1:] if arg.startswith('of='))
    pathlib.Path(target).write_bytes(data)
else:
    try:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
    except BrokenPipeError:
        os._exit(72)
if tool == 'pv' and '-n' in sys.argv:
    print('0\n50\n100', file=sys.stderr, flush=True)
sys.exit(42 if tool == failure else 0)
'''


def extracted_script():
    source = SCRIPT.read_text()
    shell = source.splitlines()[0]
    options = re.search(r"^set -[^\n]+$", source, re.MULTILINE).group()
    start = source.index('log "正在寫入映像到')
    prefix = """
log() { printf '%s\\n' "$*"; }
ok() { printf '%s\\n' "$*"; }
warn() { printf '%s\\n' "$*"; }
err() { printf '%s\\n' "$*" >&2; }
fail() { err "$*"; exit 1; }
"""
    return shell + "\n" + options + "\n" + prefix + source[start:]


class StreamWriteTests(unittest.TestCase):
    def run_case(self, mode, failure="", fifo_failure=False, reader_failure=False, cancel_signal=None, startup_signal=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        binaries = root / "bin"
        binaries.mkdir()
        scratch = root / "scratch"
        scratch.mkdir()
        image = root / "input.wic.zst"
        image.write_bytes(PAYLOAD)
        target = root / "output.wic"
        trace = root / "trace"
        trace.touch()
        script = root / "installer-section"
        section = extracted_script()
        if startup_signal is not None:
            # Deterministic signal exactly after fork and before $! is recorded.
            # This extra wait/kill exists only in the test's source harness.
            injection = '''write_image &
while [ ! -e "$STARTUP_READY" ]; do /bin/sleep 0.01; done
kill -SIGNAL "$$"
'''.replace("SIGNAL", signal.Signals(startup_signal).name.removeprefix("SIG"))
            self.assertIn("write_image &\n", section)
            section = section.replace("write_image &\n", injection, 1)
        if reader_failure:
            section = section.replace('log() {', '''printf() {
    case "$1" in DUDUCLAW_PROGRESS:*) return 61 ;; esac
    builtin printf "$@"
}
log() {''', 1)
        script.write_text(section)
        script.chmod(0o755)
        for tool in ("zstd", "dd", "lsblk", "umount", "sgdisk", "partprobe", "sync", "sleep"):
            path = binaries / tool
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)
        if not mode.startswith("no-pv"):
            (binaries / "pv").symlink_to(binaries / "dd")
        for tool in ("awk", "tail", "mktemp", "mkfifo", "rm", "rmdir"):
            executable = shutil.which(tool)
            if not executable:
                self.fail("host tool missing: " + tool)
            (binaries / tool).symlink_to(executable)
        if fifo_failure:
            (binaries / "mkfifo").unlink()
            (binaries / "mkfifo").write_text("#!/bin/sh\nexit 55\n")
            (binaries / "mkfifo").chmod(0o755)
        environment = {**os.environ, "PATH": str(binaries), "IMG": str(image),
                       "IMG_BYTES": str(image.stat().st_size), "TARGET_DEV": str(target),
                       "TMPDIR": str(scratch), "TRACE": str(trace), "FAIL_STAGE": failure,
                       "DUDUCLAW_INSTALL_PROGRESS": "1" if mode in ("progress", "no-pv-progress") else "0",
                       "DUDUCLAW_INSTALL_POWEROFF": "0"}
        if cancel_signal is not None or startup_signal is not None:
            environment["SLOW_STREAM"] = "1"
        if startup_signal is not None:
            environment["STARTUP_READY"] = str(root / "startup-ready")
        # A bad stream must stop before even attempting pending account injection.
        # It cannot mount anything: target is a regular file, and lsblk is empty.
        for name in ("OOBE_STATE", "PENDING_ACCOUNT", "PENDING_NETWORK"):
            environment.pop("DUDUCLAW_INSTALL_" + name + "_FILE", None)
        if failure in ("zstd", "pv", "dd") and (failure != "pv" or mode != "no-pv"):
            environment["DUDUCLAW_INSTALL_PENDING_ACCOUNT_FILE"] = str(root / "pending-account")
        process = subprocess.Popen([str(script)], env=environment, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        if cancel_signal is not None:
            expected_tools = {"zstd", "dd"} | ({"pv"} if not mode.startswith("no-pv") else set())
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                started = {line.split()[0] for line in trace.read_text().splitlines()}
                if expected_tools <= started:
                    break
                time.sleep(0.01)
            else:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)
                self.fail("fixture pipeline did not start")
            # Signal ONLY the true installer parent, as the UI's cancellation
            # would. Killing the fixture process group would hide the bug.
            process.send_signal(cancel_signal)
        try:
            stdout, stderr = process.communicate(timeout=5 if cancel_signal or startup_signal else 10)
        except subprocess.TimeoutExpired:
            # Never leave a broken fixture's child processes behind.
            # This session belongs solely to this test; collect any dedicated
            # child groups before killing our own remaining fixture processes.
            groups = set()
            owned_pids = []
            if process.poll() is None:
                groups.add(os.getpgid(process.pid))
            for line in trace.read_text().splitlines():
                pid = int(line.split()[1])
                try:
                    if os.getsid(pid) == process.pid:
                        groups.add(os.getpgid(pid))
                        owned_pids.append(pid)
                except ProcessLookupError:
                    pass
            for group in groups:
                try:
                    os.killpg(group, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    # Darwin can refuse a dead group after its leader exits.
                    # Fall back only to recorded children in our own session.
                    for pid in owned_pids:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
            process.communicate(timeout=5)
            self.fail("installer/stream children failed to exit within ten seconds")
        completed = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
        expected_signal = cancel_signal or startup_signal
        if expected_signal is not None:
            self.assertEqual(completed.returncode, 128 + expected_signal, completed.stderr)
        processes = trace.read_text().splitlines()
        # Child tools and progress FIFO reader must be gone, not merely detached.
        for line in processes:
            pid = int(line.split()[1])
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            self.fail("stream child left running: " + line)
        return completed, target.read_bytes() if target.exists() else None, processes, list(scratch.iterdir())

    def assert_failed(self, result):
        completed, _, processes, leftovers = result
        self.assertNotEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertNotIn("映像寫入完成", completed.stdout)
        self.assertNotIn("安裝完成", completed.stdout)
        self.assertNotIn("DUDUCLAW_PROGRESS:100", completed.stdout)
        self.assertNotIn("寫入初始設定", completed.stdout)
        self.assertFalse(any(line.startswith(("sgdisk ", "partprobe ")) for line in processes))
        self.assertEqual(leftovers, [], "progress FIFO/directory leaked")

    def test_zstd_prefix_failure_all_three_paths(self):
        for mode in ("progress", "interactive", "no-pv"):
            with self.subTest(mode=mode):
                self.assert_failed(self.run_case(mode, "zstd"))

    def test_pv_prefix_failure_both_pv_paths(self):
        for mode in ("progress", "interactive"):
            with self.subTest(mode=mode):
                self.assert_failed(self.run_case(mode, "pv"))

    def test_dd_prefix_failure_all_three_paths(self):
        for mode in ("progress", "interactive", "no-pv"):
            with self.subTest(mode=mode):
                self.assert_failed(self.run_case(mode, "dd"))

    def test_success_exact_original_bytes_all_three_paths(self):
        for mode in ("progress", "interactive", "no-pv"):
            with self.subTest(mode=mode):
                completed, actual, processes, leftovers = self.run_case(mode)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(actual, PAYLOAD)
                self.assertIn("安裝完成", completed.stdout)
                self.assertTrue(any(line.startswith("sgdisk ") for line in processes))
                self.assertEqual(leftovers, [])
                self.assertEqual("DUDUCLAW_PROGRESS:100" in completed.stdout, mode == "progress")

    def test_no_pv_path_never_executes_pv(self):
        completed, actual, processes, _ = self.run_case("no-pv", "pv")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(actual, PAYLOAD)
        self.assertFalse(any(line.startswith("pv ") for line in processes))

    def test_fifo_creation_failure_leaves_no_children_or_files(self):
        self.assert_failed(self.run_case("progress", fifo_failure=True))

    def test_progress_reader_failure_is_fatal_and_cleans_fifo(self):
        self.assert_failed(self.run_case("progress", reader_failure=True))

    def test_sync_failure_cannot_publish_completion(self):
        self.assert_failed(self.run_case("progress", "sync"))

    def test_optional_size_listing_failure_still_requires_successful_stream(self):
        completed, actual, _, leftovers = self.run_case("progress", "listing")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(actual, PAYLOAD)
        self.assertEqual(leftovers, [])
        samples = [int(value) for value in re.findall(r"^DUDUCLAW_PROGRESS:(\d+)$", completed.stdout, re.MULTILINE)]
        self.assertEqual(samples, [0, 50, 99, 100])

    def test_progress_requested_without_pv_remains_indeterminate(self):
        completed, actual, _, leftovers = self.run_case("no-pv-progress")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(actual, PAYLOAD)
        self.assertNotIn("DUDUCLAW_PROGRESS:", completed.stdout)
        self.assertEqual(leftovers, [])

    def test_parent_term_cancels_all_three_stream_paths(self):
        for mode in ("progress", "interactive", "no-pv"):
            with self.subTest(mode=mode):
                self.assert_failed(self.run_case(mode, cancel_signal=signal.SIGTERM))

    def test_parent_int_cancels_all_three_stream_paths(self):
        for mode in ("progress", "interactive", "no-pv"):
            with self.subTest(mode=mode):
                self.assert_failed(self.run_case(mode, cancel_signal=signal.SIGINT))

    def test_startup_signal_before_pid_record_is_not_lost(self):
        for sent_signal in (signal.SIGTERM, signal.SIGINT):
            for mode in ("progress", "interactive", "no-pv"):
                with self.subTest(signal=sent_signal, mode=mode):
                    self.assert_failed(self.run_case(mode, startup_signal=sent_signal))


if __name__ == "__main__":
    unittest.main(verbosity=2)
