#!/usr/bin/env python3
"""Run the real generic kernel .config guard against synthetic configurations."""
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RECIPE = ROOT / "meta-duduclaw/recipes-kernel/linux/linux-yocto_6.18.bbappend"
FRAGMENT = RECIPE.parent / "linux-yocto/duduclaw-gce-guest.cfg"
GUEST = {"CONFIG_HYPERVISOR_GUEST", "CONFIG_PARAVIRT", "CONFIG_KVM_GUEST", "CONFIG_PARAVIRT_CLOCK"}
PROVIDER = {"CONFIG_VIRTIO_PCI", "CONFIG_SCSI_VIRTIO", "CONFIG_VIRTIO_NET", "CONFIG_PCI_MSI"}


def recipe_guard():
    source = RECIPE.read_text()
    options = re.search(r'^DUDUCLAW_GCE_REQUIRED_KCONFIG = "([^"\n]+)"$', source, re.M)
    body = re.search(r'^do_configure:append:duduclaw-genericx86-64\(\) \{\n(.*?)^\}', source, re.M | re.S)
    if options is None or body is None:
        raise AssertionError("generic effective-config build guard missing")
    return options[1].split(), body[1]


def run_guard(values, missing_file=False, spaces=False):
    required, body = recipe_guard()
    with tempfile.TemporaryDirectory(prefix="gce kernel " if spaces else "gce-kernel-") as directory:
        build = Path(directory)
        if not missing_file:
            (build / ".config").write_text("\n".join(key + "=" + value for key, value in values.items()) + "\n")
        body = body.replace("${DUDUCLAW_GCE_REQUIRED_KCONFIG}", " ".join(shlex.quote(value) for value in required))
        body = body.replace("${B}", str(build))
        fatal = "bbfatal() { printf '%s\\n' \"$*\" >&2; exit 1; }\n"
        return subprocess.run(["/bin/sh", "-eu", "-c", fatal + body], text=True, capture_output=True)


class GceKernelGuestTests(unittest.TestCase):
    def good(self):
        return {key: "y" for key in GUEST | PROVIDER}

    def test_fragment_requests_guest_dependencies_without_host_kvm_change(self):
        self.assertTrue(FRAGMENT.is_file(), "generic guest fragment missing")
        values = dict(line.split("=", 1) for line in FRAGMENT.read_text().splitlines() if line.startswith("CONFIG_"))
        self.assertEqual(values, {key: "y" for key in GUEST})
        host = (FRAGMENT.parent / "duduclaw-kvm.cfg").read_text()
        for key in ("CONFIG_KVM", "CONFIG_KVM_INTEL", "CONFIG_KVM_AMD"):
            self.assertIn(key + "=m", host)
            self.assertNotIn(key, values)

    def test_fragment_and_guard_are_generic_only(self):
        source = RECIPE.read_text()
        additions = re.findall(r'^(SRC_URI[^=\n]*)= "[^"\n]*file://duduclaw-gce-guest.cfg[^"\n]*"$', source, re.M)
        self.assertEqual([value.strip() for value in additions], ["SRC_URI:append:duduclaw-genericx86-64"])
        required, body = recipe_guard()
        self.assertEqual(set(required), {key + "=y" for key in GUEST | PROVIDER})
        self.assertIn('"${B}/.config"', body)

    def test_effective_config_with_all_builtins_passes(self):
        result = run_guard(self.good())
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_original_generic_missing_guest_options_refused(self):
        # The observed 6.18.24 generic .config had provider drivers=y but no guest options.
        result = run_guard({key: "y" for key in PROVIDER})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CONFIG_HYPERVISOR_GUEST=y", result.stderr)

    def test_every_missing_required_option_refused(self):
        for key in GUEST | PROVIDER:
            with self.subTest(key=key):
                values = self.good()
                values.pop(key)
                result = run_guard(values)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(key + "=y", result.stderr)

    def test_module_does_not_satisfy_builtin_requirement(self):
        for key in GUEST | PROVIDER:
            with self.subTest(key=key):
                values = self.good()
                values[key] = "m"
                self.assertNotEqual(run_guard(values).returncode, 0)

    def test_disabled_or_inexact_value_refused(self):
        for value in ("n", "y_extra"):
            with self.subTest(value=value):
                values = self.good()
                values["CONFIG_KVM_GUEST"] = value
                self.assertNotEqual(run_guard(values).returncode, 0)

    def test_missing_config_refused(self):
        self.assertNotEqual(run_guard(self.good(), missing_file=True).returncode, 0)

    def test_build_path_with_spaces_works(self):
        result = run_guard(self.good(), spaces=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_host_kvm_modules_remain_valid(self):
        values = self.good()
        values.update(CONFIG_KVM="m", CONFIG_KVM_INTEL="m", CONFIG_KVM_AMD="m")
        result = run_guard(values)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
