#!/usr/bin/env python3
"""Patch regression; --upstream-init also checks the exact pinned oe-core init."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RECIPE = ROOT / "meta-duduclaw/recipes-core/initrdscripts/initramfs-framework_%.bbappend"
PATCH = RECIPE.parent / "initramfs-framework/0001-init-set-run-tmpfs-mode.patch"
OLD = "mount -t tmpfs tmpfs /run"
NEW = "mount -t tmpfs -o mode=0755 tmpfs /run"
PIN = "a69373d2441cb29acb6e0f7655dc8289de6be788f10c46bf5c67c04b06d0aebf"
SOURCE = "\n" * 83 + "mkdir -p /proc /sys /run\nmount -t proc proc /proc\nmount -t sysfs sysfs /sys\n" + OLD + "\nmkdir -p /run/lock\n\nif [ -d $EFI_DIR ];then\n"


def apply(source):
    with tempfile.TemporaryDirectory(prefix="initramfs-run-mode-") as directory:
        path = Path(directory) / "init"
        path.write_text(source)
        result = subprocess.run(["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-i", str(PATCH)], cwd=directory, text=True, capture_output=True)
        return result, path.read_text()


class RunModeTests(unittest.TestCase):
    def test_recipe_wires_the_patch(self):
        self.assertTrue(RECIPE.is_file(), "initramfs framework append missing")
        source = RECIPE.read_text()
        self.assertIn('FILESEXTRAPATHS:prepend := "${THISDIR}/initramfs-framework:"', source)
        self.assertIn('SRC_URI += "file://0001-init-set-run-tmpfs-mode.patch"', source)
        self.assertTrue(PATCH.is_file())

    def test_exact_patch_changes_only_run_mount_mode(self):
        self.assertTrue(PATCH.is_file(), "run mount patch missing")
        result, changed = apply(SOURCE)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = (result.stdout + result.stderr).lower()
        self.assertNotIn("fuzz", output)
        self.assertNotIn("offset", output)
        self.assertEqual(SOURCE.count(OLD + "\n"), 1)
        self.assertEqual(changed, SOURCE.replace(OLD + "\n", NEW + "\n", 1))

    def test_changed_upstream_context_refused(self):
        self.assertTrue(PATCH.is_file(), "run mount patch missing")
        source = SOURCE.replace(OLD, "mount -t tmpfs upstream-new /run")
        result, changed = apply(source)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(changed, source)

    def test_already_fixed_source_refused(self):
        self.assertTrue(PATCH.is_file(), "run mount patch missing")
        source = SOURCE.replace(OLD, NEW)
        result, changed = apply(source)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(changed, source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--upstream-init", type=Path)
    args, rest = parser.parse_known_args()
    if args.upstream_init:
        raw = args.upstream_init.read_bytes()
        if hashlib.sha256(raw).hexdigest() != PIN:
            raise SystemExit("upstream init is not the selected oe-core pin")
        SOURCE = raw.decode()
    unittest.main(argv=[__file__, *rest])
