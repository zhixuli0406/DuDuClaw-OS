#!/usr/bin/env python3
"""Post-build A/B layout verification + per-slot UKI derivation.

Runs on the BUILD HOST (pure stdlib, no mount, no loop device, no root) right
after mkosi produces mkosi.output/. Two jobs:

  1. Assert the A/B invariants that turn a bootable image into a *rollbackable*
     one. Every one of these is something that fails silently if it regresses:
     a partition label that stops matching systemd-sysupdate's pattern, a UKI
     filename that stops matching its transfer, or — the dangerous one — a UKI
     whose baked `root=PARTUUID=` does not point at slot A.

  2. Derive the slot-B twin of the UKI. mkosi bakes slot A's PARTUUID into the
     one UKI it builds; the A/B design (see
     commercial/docs/DESIGN-ab-update-rollback-2026-08.md §4.3, option A)
     needs a second UKI identical in every byte except that UUID, so that
     sd-boot's boot counting retires a kernel and its matching root together.

Why a byte-level UUID rewrite and not a ukify rebuild: the two UUIDs are both
exactly 36 ASCII characters, so the substitution changes no section size, no
PE header, no offset — it cannot produce a structurally different UKI. Building
a second UKI from vmlinuz + initrd would mean reproducing mkosi's exact stub,
microcode and kernel-modules-initrd assembly, which is a much larger surface to
get subtly wrong for zero benefit.

Exit code is non-zero on any failed assertion — a broken A/B layout must stop
the build, not reach a machine.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
import uuid
from pathlib import Path

# GPT type GUIDs, Discoverable Partitions Specification.
GPT_ESP = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b")
GPT_ROOT_X86_64 = uuid.UUID("4f68bce3-e8cd-4db1-96e7-fbcaf984b709")
GPT_ROOT_ARM64 = uuid.UUID("b921b045-1df0-41c3-af44-4c6f280d3fae")
GPT_ROOT_TYPES = {GPT_ROOT_X86_64: "x86-64", GPT_ROOT_ARM64: "arm64"}

SECTOR = 512
# systemd-sysupdate's reserved "this slot is free" partition label.
EMPTY_SLOT_LABEL = "_empty"


class Fail(Exception):
    """An A/B layout invariant was violated."""


# --------------------------------------------------------------------------
# GPT
# --------------------------------------------------------------------------


class Partition:
    def __init__(self, index: int, type_uuid: uuid.UUID, part_uuid: uuid.UUID,
                 first_lba: int, last_lba: int, attrs: int, label: str) -> None:
        self.index = index
        self.type_uuid = type_uuid
        self.part_uuid = part_uuid
        self.first_lba = first_lba
        self.last_lba = last_lba
        self.attrs = attrs
        self.label = label

    @property
    def offset(self) -> int:
        return self.first_lba * SECTOR

    def __repr__(self) -> str:
        return (f"p{self.index}(label={self.label!r} "
                f"partuuid={self.part_uuid} attrs=0x{self.attrs:016x})")


def read_gpt(raw: Path) -> list[Partition]:
    with raw.open("rb") as f:
        f.seek(SECTOR)
        header = f.read(92)
        if header[:8] != b"EFI PART":
            raise Fail(f"{raw}: no GPT header at LBA 1 (found {header[:8]!r})")
        entries_lba, entry_count, entry_size = struct.unpack_from("<QII", header, 72)
        f.seek(entries_lba * SECTOR)
        blob = f.read(entry_count * entry_size)

    parts: list[Partition] = []
    for i in range(entry_count):
        raw_entry = blob[i * entry_size:(i + 1) * entry_size]
        if raw_entry[:16] == b"\0" * 16:
            continue
        # GPT stores the two UUIDs mixed-endian, same as Python's bytes_le.
        parts.append(Partition(
            index=i + 1,
            type_uuid=uuid.UUID(bytes_le=raw_entry[0:16]),
            part_uuid=uuid.UUID(bytes_le=raw_entry[16:32]),
            first_lba=struct.unpack_from("<Q", raw_entry, 32)[0],
            last_lba=struct.unpack_from("<Q", raw_entry, 40)[0],
            attrs=struct.unpack_from("<Q", raw_entry, 48)[0],
            label=raw_entry[56:128].decode("utf-16-le").rstrip("\0"),
        ))
    return parts


# --------------------------------------------------------------------------
# PE / UKI
# --------------------------------------------------------------------------


def pe_sections(data: bytes) -> dict[str, tuple[int, int]]:
    """Map section name -> (raw offset, raw size) for a PE/COFF image."""
    if data[:2] != b"MZ":
        raise Fail("UKI is not a PE image (missing MZ signature)")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off:pe_off + 4] != b"PE\0\0":
        raise Fail("UKI is not a PE image (missing PE signature)")
    n_sections = struct.unpack_from("<H", data, pe_off + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe_off + 20)[0]
    table = pe_off + 24 + opt_size

    out: dict[str, tuple[int, int]] = {}
    for i in range(n_sections):
        entry = table + i * 40
        name = data[entry:entry + 8].rstrip(b"\0").decode("ascii", "replace")
        # Section header layout: VirtualSize@8, VirtualAddress@12,
        # SizeOfRawData@16, PointerToRawData@20.
        _vsize, _vaddr, raw_size, raw_ptr = struct.unpack_from("<IIII", data, entry + 8)
        out[name] = (raw_ptr, raw_size)
    return out


def uki_cmdline_span(data: bytes) -> tuple[int, int, str]:
    """Return (offset, size, text) of the UKI's .cmdline section."""
    sections = pe_sections(data)
    if ".cmdline" not in sections:
        raise Fail("UKI has no .cmdline section")
    off, size = sections[".cmdline"]
    text = data[off:off + size].split(b"\0", 1)[0].decode("utf-8", "replace")
    return off, size, text


def find_root_partuuid(cmdline: str) -> uuid.UUID:
    token = "root=PARTUUID="
    idx = cmdline.find(token)
    if idx < 0:
        raise Fail(
            "the UKI's kernel cmdline has no root=PARTUUID=.\n"
            "  cmdline was: " + cmdline.strip() + "\n"
            "  mkosi only substitutes the bare literal token `root=PARTUUID`\n"
            "  when it appears as a standalone word in KernelCommandLine= —\n"
            "  check appliance/mkosi.conf. Without it the machine falls back to\n"
            "  gpt-auto root discovery, and A/B rollback cannot bind a kernel to\n"
            "  its own root partition."
        )
    value = cmdline[idx + len(token):idx + len(token) + 36]
    try:
        return uuid.UUID(value)
    except ValueError as exc:
        raise Fail(f"root=PARTUUID= value {value!r} is not a UUID: {exc}") from exc


# --------------------------------------------------------------------------
# FAT32 (read-only, just enough to list the ESP's /EFI/Linux)
# --------------------------------------------------------------------------


def fat32_list(raw: Path, part: Partition, path: str) -> list[tuple[str, int]]:
    """List (name, size) of a directory inside a FAT32 partition."""
    with raw.open("rb") as f:
        f.seek(part.offset)
        bs = f.read(512)
        bytes_per_sector = struct.unpack_from("<H", bs, 0x0B)[0]
        sectors_per_cluster = bs[0x0D]
        reserved_sectors = struct.unpack_from("<H", bs, 0x0E)[0]
        num_fats = bs[0x10]
        fat_size = struct.unpack_from("<I", bs, 0x24)[0]
        root_cluster = struct.unpack_from("<I", bs, 0x2C)[0]
        if not bytes_per_sector or not sectors_per_cluster or not fat_size:
            raise Fail(f"partition {part.index} does not look like FAT32")

        fat_off = part.offset + reserved_sectors * bytes_per_sector
        data_off = fat_off + num_fats * fat_size * bytes_per_sector
        cluster_bytes = sectors_per_cluster * bytes_per_sector

        f.seek(fat_off)
        fat = f.read(fat_size * bytes_per_sector)

        def chain(start: int) -> list[int]:
            out, cur = [], start
            while 2 <= cur < 0x0FFFFFF8 and len(out) < 1 << 20:
                out.append(cur)
                cur = struct.unpack_from("<I", fat, cur * 4)[0] & 0x0FFFFFFF
            return out

        def read_dir(start_cluster: int) -> list[tuple[str, int, int, int]]:
            """-> [(name, attr, first_cluster, size)]"""
            blob = b""
            for c in chain(start_cluster):
                f.seek(data_off + (c - 2) * cluster_bytes)
                blob += f.read(cluster_bytes)

            entries: list[tuple[str, int, int, int]] = []
            lfn_parts: dict[int, str] = {}
            for i in range(0, len(blob), 32):
                e = blob[i:i + 32]
                if len(e) < 32 or e[0] == 0x00:
                    break
                if e[0] == 0xE5:
                    lfn_parts.clear()
                    continue
                attr = e[0x0B]
                if attr == 0x0F:  # long filename fragment
                    seq = e[0] & 0x1F
                    chunk = (e[1:11] + e[14:26] + e[28:32]).decode("utf-16-le", "replace")
                    lfn_parts[seq] = chunk.split("￿")[0].split("\0")[0]
                    continue
                if lfn_parts:
                    name = "".join(lfn_parts[k] for k in sorted(lfn_parts))
                    lfn_parts = {}
                else:
                    stem = e[0:8].decode("ascii", "replace").rstrip()
                    ext = e[8:11].decode("ascii", "replace").rstrip()
                    name = f"{stem}.{ext}" if ext else stem
                cluster = (struct.unpack_from("<H", e, 0x14)[0] << 16) | \
                          struct.unpack_from("<H", e, 0x1A)[0]
                size = struct.unpack_from("<I", e, 0x1C)[0]
                entries.append((name, attr, cluster, size))
            return entries

        cluster = root_cluster
        for component in [c for c in path.split("/") if c]:
            match = next(
                (e for e in read_dir(cluster)
                 if e[0].lower() == component.lower() and e[1] & 0x10),
                None,
            )
            if match is None:
                raise Fail(f"ESP has no directory {path!r} (missing {component!r})")
            cluster = match[2]

        # 0x10 = subdirectory, 0x08 = volume label (the FAT volume name lives in
        # the root directory as a pseudo-entry and is not a file).
        return [(name, size) for name, attr, _c, size in read_dir(cluster)
                if not attr & 0x18 and name not in (".", "..")]


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", required=True, type=Path, help="whole-disk image built by mkosi")
    ap.add_argument("--uki", required=True, type=Path, help="standalone UKI mkosi emitted")
    ap.add_argument("--version", required=True, help="image version (contents of mkosi.version)")
    ap.add_argument("--outdir", type=Path, default=None,
                    help="where to write the per-slot UKIs (default: --uki's directory)")
    ap.add_argument("--no-derive", action="store_true",
                    help="run the assertions only, do not write per-slot UKIs")
    args = ap.parse_args()

    outdir = args.outdir or args.uki.parent
    expected_a_label = f"duduclaw-os_{args.version}"

    parts = read_gpt(args.raw)
    print(f"[uki-slots] GPT of {args.raw.name}:")
    for p in parts:
        print(f"[uki-slots]   {p}")

    esps = [p for p in parts if p.type_uuid == GPT_ESP]
    roots = [p for p in parts if p.type_uuid in GPT_ROOT_TYPES]
    if len(esps) != 1:
        raise Fail(f"expected exactly 1 ESP, found {len(esps)}")
    if len(roots) != 2:
        raise Fail(f"expected exactly 2 root partitions (A/B), found {len(roots)}")

    roots.sort(key=lambda p: p.index)
    slot_a, slot_b = roots
    arch = GPT_ROOT_TYPES[slot_a.type_uuid]
    if slot_b.type_uuid != slot_a.type_uuid:
        raise Fail("the two root partitions have different GPT types; both slots "
                   "must use the same native root type or sysupdate will only "
                   "ever see one of them")

    size_a = slot_a.last_lba - slot_a.first_lba + 1
    size_b = slot_b.last_lba - slot_b.first_lba + 1
    if size_a != size_b:
        raise Fail(f"slot A and slot B differ in size ({size_a} vs {size_b} sectors); "
                   "sysupdate writes a slot-sized raw image with no resize step")

    # Labels are systemd-sysupdate's version ledger, not decoration.
    if slot_a.label != expected_a_label:
        raise Fail(
            f"slot A label is {slot_a.label!r}, expected {expected_a_label!r}.\n"
            "  mkosi.repart/20-root-a.conf's Label= and mkosi.version have drifted.\n"
            "  systemd-sysupdate matches installed instances on this label, so a\n"
            "  mismatch means `systemd-sysupdate list` reports nothing installed."
        )
    if slot_b.label != EMPTY_SLOT_LABEL:
        raise Fail(
            f"slot B label is {slot_b.label!r}, expected {EMPTY_SLOT_LABEL!r}.\n"
            "  That exact string is systemd-sysupdate's reserved marker for a free\n"
            "  slot; without it there is nowhere for an update to be written."
        )

    uki_bytes = args.uki.read_bytes()
    cmd_off, cmd_size, cmdline = uki_cmdline_span(uki_bytes)
    baked = find_root_partuuid(cmdline)
    print(f"[uki-slots] UKI cmdline: {cmdline.strip()}")
    if baked != slot_a.part_uuid:
        raise Fail(
            f"the UKI boots root=PARTUUID={baked}, but slot A is {slot_a.part_uuid}.\n"
            "  mkosi substitutes the PARTUUID of the FIRST root-typed partition,\n"
            "  so this means the repart drop-in ordering changed. Shipping this\n"
            "  image would boot a kernel against the wrong (or empty) slot."
        )

    esp_files = fat32_list(args.raw, esps[0], "/EFI/Linux")
    print(f"[uki-slots] ESP /EFI/Linux: {esp_files}")
    # Tolerates the boot-counting suffix (`+3`, `+2-1`) that H3b will add.
    installed = [n for n, _s in esp_files
                 if n == f"{expected_a_label}.efi" or n.startswith(f"{expected_a_label}+")]
    if len(installed) != 1:
        raise Fail(
            f"expected exactly one UKI named {expected_a_label}.efi (optionally with a\n"
            f"  boot-counting suffix) under the ESP's /EFI/Linux, found {esp_files}.\n"
            "  The name is set by mkosi.conf's UnifiedKernelImageFormat= and MUST\n"
            "  match mkosi.extra/etc/sysupdate.d/20-duduclaw-uki.transfer's target\n"
            "  MatchPattern=, or sysupdate cannot account for the UKI in the ESP."
        )
    esp_size = dict(esp_files)[installed[0]]
    if esp_size != len(uki_bytes):
        raise Fail(f"ESP's {installed[0]} is {esp_size}B but the standalone UKI is "
                   f"{len(uki_bytes)}B — they are supposed to be the same artifact")

    print(f"[uki-slots] OK: arch={arch} slotA={slot_a.part_uuid} slotB={slot_b.part_uuid} "
          f"esp_entry={installed[0]}")

    if args.no_derive:
        return 0

    # --- derive the per-slot pair -----------------------------------------
    outdir.mkdir(parents=True, exist_ok=True)
    slot_a_path = outdir / f"duduclaw-os_{args.version}.slot-a.efi"
    slot_b_path = outdir / f"duduclaw-os_{args.version}.slot-b.efi"

    slot_a_path.write_bytes(uki_bytes)

    old = f"root=PARTUUID={slot_a.part_uuid}".encode()
    new = f"root=PARTUUID={slot_b.part_uuid}".encode()
    assert len(old) == len(new), "PARTUUID text is fixed width; substitution must not resize"

    # Confine the rewrite to .cmdline so no other section can be touched.
    section = bytearray(uki_bytes[cmd_off:cmd_off + cmd_size])
    hits = section.count(old)
    if hits != 1:
        raise Fail(f"expected exactly one root=PARTUUID= in .cmdline, found {hits}")
    patched = bytearray(uki_bytes)
    patched[cmd_off:cmd_off + cmd_size] = section.replace(old, new)
    slot_b_path.write_bytes(bytes(patched))

    # Re-parse the derived artifact rather than trusting the write.
    check_off, _cs, check_cmdline = uki_cmdline_span(bytes(patched))
    if check_off != cmd_off:
        raise Fail("slot-B UKI's .cmdline moved; the substitution changed the layout")
    if find_root_partuuid(check_cmdline) != slot_b.part_uuid:
        raise Fail("slot-B UKI does not boot slot B after substitution")
    if len(patched) != len(uki_bytes):
        raise Fail("slot-B UKI changed size")

    print(f"[uki-slots] wrote {slot_a_path.name}  sha256={sha256_of(uki_bytes)}")
    print(f"[uki-slots] wrote {slot_b_path.name}  sha256={sha256_of(bytes(patched))}")
    print("[uki-slots] the two differ only in the 36 characters of root=PARTUUID=")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Fail as e:
        print(f"[uki-slots] FAIL: {e}", file=sys.stderr)
        sys.exit(1)
