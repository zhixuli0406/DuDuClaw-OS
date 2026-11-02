#!/usr/bin/env python3
"""Run the actual rootfs hook against old-disk identities; no mount/guest needed."""
from pathlib import Path
import argparse
import ast
import hashlib
import os
import re
import shlex
import subprocess
import tempfile
import unittest
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
CLASSES = ROOT / "meta-duduclaw/classes"
WKS = ROOT / "meta-duduclaw/files/wic/duduclaw-ab-bootdisk.wks.in"
ESP = "dedec1a0-0000-4000-8000-00000000000e"
DATA = "dedec1a0-0000-4000-8000-00000000000f"
# Filesystem UUIDs observed on the installed v0.4 disk and the failed new root.
OLD_FS_UUIDS = {"/boot": "B69C-770E", "/data": "902db4a9-4c16-4a16-a382-3c62ee418a99"}
WIC_ENGINE_DIR = None
NEW_FS_UUIDS = {"/boot": "0CF1-C8F8", "/data": "cfb08bb6-3c0f-4d0b-9ccb-c8c5f0adfe3b"}


def hook_source():
    matches = []
    for name in ("duduclaw-ab-partflags.bbclass", "duduclaw-verity.bbclass"):
        text = (CLASSES / name).read_text()
        for match in re.finditer(r"^(duduclaw_(?:ab|verity)_static_fstab) \(\) \{\n(.*?)^\}", text, re.M | re.S):
            matches.append((match[1], match[2], text))
    if len(matches) != 1:
        raise AssertionError("exactly one shared persistent fstab writer required")
    name, body, text = matches[0]
    if f'ROOTFS_POSTPROCESS_COMMAND += "{name}; "' not in text:
        raise AssertionError("fstab writer is not connected to rootfs generation")
    return body


def generate(verity):
    with tempfile.TemporaryDirectory(prefix="ab-persistent-mounts-") as directory:
        root = Path(directory)
        (root / "etc").mkdir()
        initial = "/dev/root / auto ro 1 1\nproc /proc proc defaults 0 0\n"
        path = root / "etc/fstab"
        path.write_text(initial)
        body = hook_source()
        for key, value in {"IMAGE_ROOTFS": str(root), "sysconfdir": "/etc",
                           "DUDUCLAW_VERITY_ENABLE": str(verity),
                           "DUDUCLAW_AB_ESP_PARTUUID": ESP,
                           "DUDUCLAW_AB_DATA_PARTUUID": DATA}.items():
            body = body.replace("${" + key + "}", value)
        result = subprocess.run(["sh", "-eu", "-c", "fixture_hook() {\n" + body + "\n}\nfixture_hook"], text=True, capture_output=True)
        if result.returncode:
            raise AssertionError(result.stderr)
        return initial, path.read_text()


def entries(text):
    return [line.split() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]


class PersistentMountTests(unittest.TestCase):
    def test_new_root_mounts_existing_esp_and_data_with_different_filesystem_uuids(self):
        for verity in (0, 1):
            with self.subTest(verity=verity):
                initial, output = generate(verity)
                self.assertTrue(output.startswith(initial), "root and unrelated mounts changed")
                mounts = {row[1]: row for row in entries(output)}
                for mount, partuuid, fstype in (("/boot", ESP, "vfat"), ("/data", DATA, "ext4")):
                    self.assertNotEqual(OLD_FS_UUIDS[mount], NEW_FS_UUIDS[mount])
                    self.assertIn(mount, mounts, "persistent mount missing from new root")
                    self.assertEqual(mounts[mount][0], "PARTUUID=" + partuuid)
                    self.assertEqual(mounts[mount][2], fstype)
                    self.assertNotIn(NEW_FS_UUIDS[mount], output)
                    self.assertEqual(sum(row[1] == mount for row in entries(output)), 1)
                self.assertTrue({"nosuid", "nodev", "x-systemd.growfs"}.issubset(set(mounts["/data"][3].split(","))))
                self.assertEqual(mounts["/data"][4:], ["0", "2"])
                self.assertEqual(mounts["/boot"][3:], ["defaults", "0", "0"])

    def test_wic_cannot_inject_factory_filesystem_uuids(self):
        parts = {args[1]: args for args in (shlex.split(line) for line in WKS.read_text().splitlines() if line.startswith("part /"))}
        # This flag protects the ROOT filesystem receiving the generated fstab.
        # Flags on ESP/DATA do not exclude their rows from update_fstab().
        self.assertIn("--no-fstab-update", parts["/"])
        for mount, variable in (("/boot", "DUDUCLAW_AB_ESP_PARTUUID"), ("/data", "DUDUCLAW_AB_DATA_PARTUUID")):
            with self.subTest(mount=mount):
                args = parts[mount]
                self.assertIn("--uuid=${" + variable + "}", args)
                self.assertFalse(any(arg.startswith("--fsuuid") for arg in args), "must not force the old filesystem identity")
        self.assertIn("--uuid=${DUDUCLAW_AB_ROOTA_PARTUUID}", parts["/"])
        self.assertNotIn("--use-label", parts["/"])

    def test_actual_pinned_wic_generator_and_root_writer_gate(self):
        if WIC_ENGINE_DIR is None:
            self.skipTest("pass --wic-engine-dir for pinned-engine regression; no engine proof without it")
        paths = (("plugins/imager/direct.py", "d81c21da57ccf834bbf0a20f4a967898b89e51d3cdc49ca1da44a48530339080"),
                 ("partition.py", "8d08b63a1fc2615819c9651e1536c9360cc67f2816e89c1402b0a9558fea1a9b"))
        methods = []
        for (relative, expected), cls, method in zip(paths, ("DirectPlugin", "Partition"), ("update_fstab", "prepare_rootfs_ext")):
            raw = (WIC_ENGINE_DIR / relative).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), expected, "wrong pinned Wic engine")
            tree = ast.parse(raw)
            owner = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == cls)
            methods.append(next(node for node in owner.body if isinstance(node, ast.FunctionDef) and node.name == method))
        namespace = {"os": os}
        exec(compile(ast.Module(body=[methods[0]], type_ignores=[]), "pinned-wic-update-fstab", "exec"), namespace)
        gates = [node.test for node in ast.walk(methods[1]) if isinstance(node, ast.If)
                 and ast.unparse(node.test) == "self.updated_fstab_path and self.has_fstab and (not self.no_fstab_update)"]
        self.assertEqual(len(gates), 2, "both original fstab write/mtime gates must remain pinned")
        gate = compile(ast.Expression(body=gates[0]), "pinned-wic-root-writer-gate", "eval")
        lines = [shlex.split(line) for line in WKS.read_text().splitlines() if line.startswith("part /")]
        root_args = next(args for args in lines if args[1] == "/")
        # Simulate only metadata passed to the exact engine method, never disks.
        parts = []
        for mount, number, fsuuid in (("/boot", 1, "0x0CF1C8F8"), ("/data", 4, NEW_FS_UUIDS["/data"])):
            args = next(args for args in lines if args[1] == mount)
            values = dict(arg[2:].split("=", 1) for arg in args if arg.startswith("--") and "=" in arg)
            parts.append(SimpleNamespace(realnum=number, mountpoint=mount, use_uuid="--use-uuid" in args,
                         use_label="--use-label" in args, fsuuid=fsuuid, uuid=ESP if number == 1 else DATA,
                         disk="sda", label="boot" if number == 1 else "duduclaw-data",
                         fstype="vfat" if number == 1 else "ext4", fsopts=values.get("fsoptions", ""),
                         fspassno=values.get("fspassno", "")))
        _, static = generate(0)
        with tempfile.TemporaryDirectory(prefix="pinned-wic-fstab-") as directory:
            directory = Path(directory)
            (directory / "etc").mkdir()
            (directory / "etc/fstab").write_text(static)
            context = SimpleNamespace(parts=parts, workdir=str(directory), updated_fstab_path=None)
            namespace["update_fstab"](context, str(directory))
            generated = Path(context.updated_fstab_path).read_text()
            self.assertEqual(sum(row[1] == "/boot" for row in entries(generated)), 2)
            self.assertEqual(sum(row[1] == "/data" for row in entries(generated)), 2)
            context.has_fstab = True
            context.no_fstab_update = "--no-fstab-update" in root_args
            writes_generated = bool(eval(gate, {"self": context}))
            self.assertFalse(writes_generated, "Wic would overwrite the root with duplicate factory mount rows")
            # Negative control: removing the ROOT flag reopens the actual writer.
            context.no_fstab_update = False
            self.assertTrue(eval(gate, {"self": context}))
            self.assertNotEqual(generated, static)

    def test_both_shipping_editions_share_the_hook(self):
        base = (ROOT / "meta-duduclaw/recipes-core/images/duduclaw-image-ab.bb").read_text()
        desktop = (ROOT / "meta-duduclaw/recipes-core/images/duduclaw-image-appliance.bb").read_text()
        self.assertIn("inherit duduclaw-ab-partflags", base)
        self.assertIn("require recipes-core/images/duduclaw-image-ab.bb", desktop)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--wic-engine-dir", type=Path)
    args, remaining = parser.parse_known_args()
    WIC_ENGINE_DIR = args.wic_engine_dir
    unittest.main(argv=[__file__, *remaining])
