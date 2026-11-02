#!/usr/bin/env python3
"""Host-only tests of shell validators; no real-guest acceptance is claimed."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
LIB = HERE / "validators.sh"

INPUT = '''table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        ct state established,related accept
        ct state invalid drop
        icmp type { destination-unreachable, echo-request, time-exceeded } accept
        icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, echo-request, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
        udp dport 5353 accept comment "mDNS"
        tcp dport 18789 accept
        ip saddr @maintenance_src4 tcp dport @maintenance_tcp_ports accept
        ip6 saddr @maintenance_src6 tcp dport @maintenance_tcp_ports accept
        tcp dport @maintenance_tcp_ports reject with tcp reset
    }
}'''
OUTPUT = '''table inet filter {
    chain output {
        type filter hook output priority filter; policy accept;
        oif "lo" jump duduclaw_maint_egress
        oif "lo" jump duduclaw_podman_egress
    }
}'''
EGRESS = '''table inet filter {
    chain duduclaw_maint_egress {
        meta skuid 4800 counter packets 4 bytes 256 reject
    }
}'''


class Validators(unittest.TestCase):
    def validate(self, name, *args, want=True):
        result = subprocess.run(
            ["sh", "-c", '. "$1"; shift; "$@"', "validator", str(LIB), name, *args],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode == 0, want, (name, args, result.stderr))

    def test_exec_is_single_exact_command(self):
        good = "{ path=/usr/sbin/dropbear ; argv[]=/usr/sbin/dropbear -s -c /menu ; ignore_errors=yes ; pid=0 }"
        for raw, want in [(good, True), (good + good, False), ("", False),
                          (good.replace(" -s ", " "), False),
                          (good.replace("/menu ;", "/menu -R ;"), False)]:
            with self.subTest(raw=raw):
                self.validate("maint_exec_exact", raw, "/usr/sbin/dropbear", "/usr/sbin/dropbear -s -c /menu", want=want)

    def test_security_tokens_are_whole_tokens(self):
        self.validate("maint_has_token", "a.service duduclaw-sysd.service", "duduclaw-sysd.service")
        self.validate("maint_has_token", "evil-duduclaw-sysd.service", "duduclaw-sysd.service", want=False)
        self.validate("maint_same_tokens", "::/0 0.0.0.0/0", "0.0.0.0/0 ::/0")
        self.validate("maint_same_tokens", "0.0.0.0/0", "0.0.0.0/0 ::/0", want=False)
        self.validate("maint_same_tokens", "::/0 ::/0 0.0.0.0/0", "0.0.0.0/0 ::/0", want=False)

    def test_nft_input_rejects_broadened_policy(self):
        self.validate("maint_nft_input_ok", INPUT)
        for bad in ["", INPUT.replace("policy drop", "policy accept"),
                    INPUT.replace('iif "lo" accept', 'accept\n        iif "lo" accept'),
                    INPUT.replace("ip saddr @maintenance_src4 ", ""),
                    INPUT.replace("nd-neighbor-advert }", "nd-neighbor-advert, redirect }"),
                    INPUT.replace("tcp dport 18789", "tcp dport 22"),
                    INPUT.replace("reject with tcp reset", "accept")]:
            with self.subTest(bad=bad):
                self.validate("maint_nft_input_ok", bad, want=False)

    def test_nft_output_jump_cannot_be_bypassed(self):
        self.validate("maint_nft_output_ok", OUTPUT)
        for bad in ["", OUTPUT.replace("hook output", "hook input"),
                    OUTPUT.replace('oif "lo" jump duduclaw_maint_egress', 'accept\n        oif "lo" jump duduclaw_maint_egress'),
                    OUTPUT.replace("jump duduclaw_maint_egress", "jump fake_duduclaw_maint_egress")]:
            self.validate("maint_nft_output_ok", bad, want=False)

    def test_nft_egress_exact_uid_and_no_other_rules(self):
        self.validate("maint_nft_egress_ok", EGRESS)
        for bad in ["", EGRESS.replace("4800", "1000"), EGRESS.replace("reject", "accept"),
                    EGRESS.replace("reject", "reject\n        accept"),
                    EGRESS.replace("meta skuid", "type filter hook output priority 0; policy accept;\n        meta skuid")]:
            self.validate("maint_nft_egress_ok", bad, want=False)

    def test_source_set_exact_membership(self):
        good = "set maintenance_src6 {\n elements = { fe80::/10,\n fc00::/7 }\n}"
        self.validate("maint_nft_sources_ok", good, "fc00::/7 fe80::/10")
        for bad in ["", good.replace("fc00::/7", "::/0"), good.replace("fc00::/7", "fc00::/7, 2001:db8::/32")]:
            self.validate("maint_nft_sources_ok", bad, "fc00::/7 fe80::/10", want=False)

    def test_unknown_kernel_config_fails(self):
        self.validate("maint_kernel_bpf_ok", "CONFIG_CGROUP_BPF=y\nCONFIG_BPF=y")
        for bad in ["", "# CONFIG_CGROUP_BPF is not set", "CONFIG_CGROUP_BPF=m", "CONFIG_CGROUP_BPF=y_fake"]:
            self.validate("maint_kernel_bpf_ok", bad, want=False)

    def test_closed_port_set_must_be_present_and_empty(self):
        empty = "table inet filter {\nset maintenance_tcp_ports {\ntype inet_service\n}\n}"
        self.validate("maint_nft_empty_ports_ok", empty)
        self.validate("maint_nft_empty_ports_ok", empty.replace("type inet_service", "type inet_service\nelements = { }"))
        for bad in ["", empty.replace("inet_service", "ipv4_addr"),
                    empty.replace("type inet_service", "type inet_service\nelements = { 22 }"),
                    empty.replace("type inet_service", "type inet_service\nelements = {\n22\n}")]:
            self.validate("maint_nft_empty_ports_ok", bad, want=False)

    def test_host_key_mutation_requires_explicit_opt_in(self):
        result = subprocess.run(
            ["sh", str(HERE / "guest-baseline.sh"), "--edition", "desktop", "--mode", "create-host-key"],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires --fresh-guest", result.stdout)
        self.assertNotIn("EVIDENCE", result.stdout)

    def test_production_ready_marker_requires_exact_bytes(self):
        source = (HERE / "guest-baseline.sh").read_text()
        ready = re.search(r"^ready_ok\(\) \{\n.*?^\}", source, re.M | re.S)
        self.assertIsNotNone(ready)
        # Execute the actual production function, substituting only its
        # absolute fixture path and the independently checked metadata gate.
        body = ready.group(0).replace(
            "/usr/lib/duduclaw/maint-ssh.ready", '"$TEST_READY_FILE"'
        )
        with tempfile.TemporaryDirectory(prefix="maint-marker-") as directory:
            marker = Path(directory) / "marker"
            for content, want in [(b"1\n", True), (b"1", False),
                                  (b"1\n\n", False), (b"1\0", False)]:
                with self.subTest(content=content):
                    marker.write_bytes(content)
                    result = subprocess.run(
                        ["sh", "-c", '. "$1"; trusted_file() { return 0; };\n' + body + '\nready_ok',
                         "ready-marker", str(LIB)],
                        env={**os.environ, "TEST_READY_FILE": str(marker)},
                        capture_output=True, text=True, timeout=5,
                    )
                    self.assertEqual(result.returncode == 0, want, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
