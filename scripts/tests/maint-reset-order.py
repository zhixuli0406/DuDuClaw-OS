#!/usr/bin/env python3
"""Check the repository's factory-reset startup ordering, without booting it.

Reads real layer unit sources and the maintenance host-key drop-in. This
checks explicit ordering and failure dependencies only; it does not model
upstream units, systemd's generated dependencies, or a running OS image.
"""

from collections import defaultdict
from pathlib import Path
import unittest


LAYER = Path(__file__).resolve().parents[2] / "meta-duduclaw"
RESET = "duduclaw-factory-reset.service"
SYSD = "duduclaw-sysd.service"
HOST_KEY = "dropbearkey.service"
GATEWAY = "duduclaw-gateway.service"


def settings(path):
    """Read repeated assignments and empty list resets in a unit source."""
    result = defaultdict(list)
    section = None
    continued = ""
    for raw in path.read_text().splitlines():
        line = continued + raw.strip()
        if line.endswith("\\"):
            continued = line[:-1] + " "
            continue
        continued = ""
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section and "=" in line:
            name, value = line.split("=", 1)
            key = (section, name.strip())
            if not value.strip():
                result[key] = []
            else:
                result[key].extend(value.split())
    return result


def reachable(graph, start, end):
    pending = list(graph[start])
    seen = {start}
    while pending:
        node = pending.pop()
        if node == end:
            return True
        if node not in seen:
            seen.add(node)
            pending.extend(graph[node])
    return False


class ResetStartupOrderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Direct recipe files only: never inspect vendored platform snapshots.
        cls.units = {}
        for suffix in ("*.service", "*.socket"):
            for path in sorted(LAYER.glob(f"recipes-*/*/files/{suffix}")):
                if path.name in cls.units:
                    raise AssertionError(f"ambiguous unit source: {path.name}")
                cls.units[path.name] = settings(path)
        cls.units[HOST_KEY] = settings(
            LAYER / "recipes-core/dropbear/files/60-duduclaw-maint-dropbearkey.conf"
        )
        cls.order = defaultdict(set)
        cls.required = defaultdict(set)
        for name, unit in cls.units.items():
            for later in unit.get(("Unit", "Before"), []):
                cls.order[name].add(later)
            for earlier in unit.get(("Unit", "After"), []):
                cls.order[earlier].add(name)
            for key in ("Requires", "Requisite", "BindsTo"):
                cls.required[name].update(unit.get(("Unit", key), []))

    def test_reset_finishes_before_sysd_can_replay_old_ssh_records(self):
        self.assertEqual(self.units[RESET][("Service", "Type")], ["oneshot"])
        self.assertTrue(
            reachable(self.order, RESET, SYSD),
            "sysd can load an old window and recreate audit data after the reset wipes it",
        )

    def test_reset_finishes_before_host_key_generation(self):
        self.assertTrue(
            reachable(self.order, RESET, HOST_KEY),
            "host-key generation must not finish before the reset removes the generated key",
        )

    def test_added_order_does_not_create_an_explicit_startup_cycle(self):
        nodes = set(self.order)
        nodes.update(later for edges in self.order.values() for later in edges)
        for node in sorted(nodes):
            self.assertFalse(reachable(self.order, node, node), f"ordering cycle at {node}")

    def test_reset_failure_does_not_become_a_required_startup_gate(self):
        for consumer in (SYSD, HOST_KEY, GATEWAY):
            self.assertFalse(
                reachable(self.required, consumer, RESET),
                f"{consumer} must still start when reset fails; use ordering only",
            )
        self.assertIn("multi-user.target", self.units[RESET][("Install", "WantedBy")])


if __name__ == "__main__":
    unittest.main(verbosity=2)
