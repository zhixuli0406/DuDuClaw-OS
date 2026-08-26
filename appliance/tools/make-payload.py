#!/usr/bin/env python3
"""H3d — build-host payload packager for the A/B update line.

Runs on the BUILD HOST (pure stdlib, no mount, no loop device, no root),
after mkosi has produced mkosi.output/ and after uki-slots.py has confirmed
the raw image's A/B layout is sane. Its job is narrow: turn one whole-disk
image + one standalone UKI into the exact three-plus-manifest bundle that
systemd-sysupdate's transfer definitions expect to find staged at
/data/duduclaw/updates/ on a machine (H3d moved staging there: /var lives on
the 5 GiB root slot and cannot hold a 5 GiB root payload):

    duduclaw-os_<version>.root-<arch>.raw   slot A's root partition, byte
                                             for byte (this is what
                                             10-duduclaw-root.transfer's
                                             MatchPattern= is written against)
    duduclaw-os_<version>.efi               a straight copy of the UKI mkosi
                                             built for slot A (matches
                                             20-duduclaw-uki.transfer's
                                             MatchPattern=)
    SHA256SUMS / SHA256SUMS.minisig         the integrity chain sysupdate
                                             itself does NOT provide for
                                             Type=regular-file sources (see
                                             the comment atop
                                             10-duduclaw-root.transfer) —
                                             whatever stages these files onto
                                             a machine must verify this
                                             signature first
    manifest.json                           human/machine-readable metadata.
                                             NOT part of the signature chain:
                                             SHA256SUMS + SHA256SUMS.minisig
                                             are the only artifacts an
                                             installer is required to trust;
                                             manifest.json is convenience
                                             provenance a curious human or a
                                             dashboard can read without
                                             re-deriving anything.

Why "slot A, always": the on-machine installer never gets to choose which
physical GPT slot receives an update — systemd-sysupdate always writes into
whichever slot is *not* currently running (that is what "_empty" versus a
labelled slot means, see mkosi.repart/). The shipped .efi is therefore a
*template*: its baked `root=PARTUUID=` points at THIS build's slot A, and
rewriting it for the destination slot before staging is the installer's job,
not this script's and not sysupdate's.

That template must be rewritten on the DEVICE, not here, and the reason is
measured rather than assumed: mkosi seeds systemd-repart with a fresh random
UUID per build, so two builds of the same image carry entirely different
partition UUIDs. A UKI shipped with the release host's PARTUUID baked in
would send a real machine into an initrd waiting forever for a partition it
does not have. crates/duduclaw-gateway/src/uki_patch.rs does the 36-character
rewrite at staging time; build.sh's uki-slots.py step still derives the
slot-A/slot-B pair, but as a build-time invariant check, not as a payload.

Companion script: uki-slots.py in this same directory owns GPT/PE parsing
(read_gpt, pe_sections, uki_cmdline_span, find_root_partuuid) — this script
imports it rather than forking a second copy that would drift.

Exit code is non-zero on any failed assertion or any tool failure (missing
minisign, a signature that does not self-verify, a short read while
extracting slot A, ...). A payload that cannot prove its own integrity on
the build host must never reach a machine.

YOCTO LINE REUSE (Y8-1, 2026-08-27): every byte-offset computation here is
pure GPT arithmetic against whatever file `--raw` points at — it does not
care whether that file was produced by mkosi (`duduclaw-os.raw`) or by
Yocto's `wic` tool (a `.wic` file is a plain raw disk image with a GPT, same
as mkosi's `.raw`). Slot selection reads the actual on-disk GPT root-type
entries via uki_slots.GPT_ROOT_TYPES, which is already keyed by GUID, not by
which build tool wrote it, so a Yocto `.wic` with SD_GPT_ROOT_X86_64-typed
root-A/root-B partitions round-trips through select_slots()/
extract_root_payload() unmodified. The ONE thing that could not be reused
as-is is `image_version`, which this script's --version-less path derives
by reading appliance/mkosi.version — a Debian-line-specific file that says
nothing about a Yocto build's own version. `--image-version` (added by this
change, optional, defaults to the old mkosi.version-reading behavior when
omitted so the Debian line's own callers see zero behavior change) lets a
Yocto caller supply meta-duduclaw's own version directly, e.g.:

    python3 appliance/tools/make-payload.py \\
        --raw meta-duduclaw/.build/<dir>/duduclaw-os-genericx86-64.wic \\
        --uki <deploy dir>/uki.efi \\
        --image-version "$(grep DUDUCLAW_PLATFORM_VERSION \\
            meta-duduclaw/conf/distro/include/duduclaw-platform-version.inc \\
            | sed -E 's/.*"(.*)".*/\\1/')" \\
        --sign-key ~/.minisign/duduclaw-os-release.key

This has NOT been run end to end against a real Yocto .wic in this session
(see the Y8-1 handoff notes) — the reasoning above is a code-level
compatibility argument, not a verified result.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

_TOOLS = Path(__file__).resolve().parent
_APPLIANCE = _TOOLS.parent

# 4 MiB: the streaming unit for extracting slot A out of a many-GB raw image
# without ever holding the whole thing in memory.
CHUNK_SIZE = 4 * 1024 * 1024

# The release-signing PUBLIC key for duduclaw-os payloads. A public key is
# not a secret — pinning it here (rather than trusting whatever --sign-key's
# directory happens to contain a .pub file for) is what makes the
# self-verification step below meaningful: it proves the SHA256SUMS we just
# produced verifies against the specific key operators and machines expect,
# not merely against *some* key that happened to sign it.
RELEASE_PUBKEY = "RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n"


def _load_uki_slots():
    """Import the sibling script despite its hyphenated filename.

    uki-slots.py cannot be `import`ed with normal syntax (Python module
    names can't contain `-`), and renaming a script whose CLI is already
    documented and invoked from build.sh just to satisfy import syntax would
    be a worse trade than one importlib indirection. Loaded at module import
    time (not lazily inside main()) so its names — including the Partition
    class used in type hints below — are available everywhere in this file,
    the same shape h3bc_probe.py uses for its own sibling helpers.
    """
    path = _TOOLS / "uki-slots.py"
    if not path.exists():
        raise SystemExit(f"[make-payload] FAIL: sibling script missing: {path}")
    spec = importlib.util.spec_from_file_location("uki_slots", path)
    if spec is None or spec.loader is None:  # pragma: no cover - environment guard
        raise SystemExit(f"[make-payload] FAIL: cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


uki_slots = _load_uki_slots()


# --------------------------------------------------------------------------
# slot selection + invariants
# --------------------------------------------------------------------------


def select_slots(parts: list["uki_slots.Partition"]) -> tuple["uki_slots.Partition", "uki_slots.Partition"]:
    """Pick slot A / slot B out of the GPT's root-typed partitions.

    Slot A is whichever root partition sits FIRST on disk (lowest first_lba)
    — a positional convention (mkosi.repart/20-root-a.conf is applied before
    21-root-b.conf), independent of GPT entry index and independent of the
    partition label. This is deliberately not the same selection uki-slots.py
    uses internally (it sorts by entry index) because the two scripts are
    answering different questions: uki-slots.py is verifying a build just
    produced by mkosi, where index order and disk order coincide by
    construction; this script may run against an arbitrary already-built
    image and should not assume that coincidence still holds.
    """
    roots = [p for p in parts if p.type_uuid in uki_slots.GPT_ROOT_TYPES]
    if len(roots) != 2:
        raise uki_slots.Fail(f"expected exactly 2 root partitions (A/B), found {len(roots)}")
    if roots[0].type_uuid != roots[1].type_uuid:
        raise uki_slots.Fail(
            "the two root partitions have different GPT types; both slots "
            "must use the same native root type for a single --arch payload "
            "to make sense"
        )
    roots.sort(key=lambda p: p.first_lba)
    return roots[0], roots[1]


def assert_slot_invariants(slot_a: "uki_slots.Partition", slot_b: "uki_slots.Partition", image_version: str) -> None:
    """Assert the raw image is a fresh, well-formed factory build.

    image_version is what mkosi.version actually contains — the value baked
    into slot A's GPT label at build time — which is NOT necessarily the
    same as the payload version this run is publishing under (--version can
    override the latter to stage a fake-upgrade payload from an unchanged
    image, which is exactly how this script's own acceptance test works).
    """
    expected_a_label = f"duduclaw-os_{image_version}"
    if slot_a.label != expected_a_label:
        raise uki_slots.Fail(
            f"slot A label is {slot_a.label!r}, expected {expected_a_label!r} "
            f"(derived from appliance/mkosi.version={image_version!r}). "
            "Either the raw image predates the current mkosi.version, or "
            "slot ordering does not match mkosi.repart/'s A/B convention — "
            "refusing to package a payload whose slot A cannot be trusted."
        )
    if slot_b.label != uki_slots.EMPTY_SLOT_LABEL:
        raise uki_slots.Fail(
            f"slot B label is {slot_b.label!r}, expected "
            f"{uki_slots.EMPTY_SLOT_LABEL!r} — this raw image does not look "
            "like a fresh factory build (slot B should still be the "
            "reserved free slot)."
        )
    size_a = slot_a.last_lba - slot_a.first_lba + 1
    size_b = slot_b.last_lba - slot_b.first_lba + 1
    if size_a != size_b:
        raise uki_slots.Fail(
            f"slot A and slot B differ in size ({size_a} vs {size_b} "
            "sectors); systemd-sysupdate writes a slot-sized raw image with "
            "no resize step, so a payload sized for slot A would not fit "
            "into slot B on install."
        )


# --------------------------------------------------------------------------
# extraction
# --------------------------------------------------------------------------


def extract_root_payload(raw_path: Path, slot: "uki_slots.Partition", dest_path: Path) -> tuple[int, str]:
    """Stream slot A's bytes out of the whole-disk image into dest_path.

    Sparse-aware: an all-zero 4 MiB chunk is skipped with a seek instead of
    written, so the payload occupies only as much real disk as it has real
    content — the appliance's /data, which stages this file before flashing,
    is small enough that the difference matters. The written file's LOGICAL
    length is still made correct via a final truncate(), and the sha256 is
    computed over every byte including the skipped zero runs — a sparse file
    and a fully-written file with the same content must hash identically.

    Returns (length_in_bytes, sha256_hex).
    """
    offset = slot.first_lba * uki_slots.SECTOR
    length = (slot.last_lba - slot.first_lba + 1) * uki_slots.SECTOR

    digest = hashlib.sha256()
    last_decile = 0
    processed = 0

    with raw_path.open("rb") as src, dest_path.open("wb") as dst:
        src.seek(offset)
        remaining = length
        while remaining > 0:
            want = min(CHUNK_SIZE, remaining)
            data = src.read(want)
            if len(data) != want:
                raise uki_slots.Fail(
                    f"{raw_path}: short read while extracting slot A "
                    f"(wanted {want}B at src offset {src.tell() - len(data)}, "
                    f"got {len(data)}B) — the raw image is truncated or was "
                    "modified while this script was reading it"
                )
            digest.update(data)
            if data.count(0) == len(data):
                dst.seek(len(data), os.SEEK_CUR)
            else:
                dst.write(data)
            processed += len(data)
            remaining -= len(data)

            decile = processed * 100 // length // 10
            if decile > last_decile:
                print(
                    f"[make-payload] extracting slot A: {decile * 10}% "
                    f"({processed // (1024 * 1024)} MiB / {length // (1024 * 1024)} MiB)"
                )
                last_decile = decile

        # Correct the final length even if the tail was all-zero chunks that
        # were only seek()ed past and never actually written — seeking past
        # current EOF does not, by itself, grow a file's apparent size.
        dst.truncate(length)

    return length, digest.hexdigest()


def copy_uki_template(uki_path: Path, dest_path: Path) -> tuple[int, str, uuid.UUID]:
    """Byte-for-byte copy the standalone UKI, after proving it is usable.

    The only thing checked here is that the UKI actually has a
    `root=PARTUUID=` token in its .cmdline section — that 36-character
    field is what the on-machine installer must locate and rewrite before
    staging this template for a specific slot (see the module docstring).
    A UKI missing that token would produce a payload that installs but can
    never be bound to a slot, so this fails the build rather than the field
    deployment.

    Returns (size_in_bytes, sha256_hex, baked_root_partuuid) — the PARTUUID
    is provenance only (recorded in manifest.json), never validated against
    slot A here, since the whole point of shipping a *template* is that its
    baked UUID is expected to be rewritten downstream.
    """
    data = uki_path.read_bytes()
    _off, _size, cmdline = uki_slots.uki_cmdline_span(data)
    baked = uki_slots.find_root_partuuid(cmdline)
    dest_path.write_bytes(data)
    return len(data), hashlib.sha256(data).hexdigest(), baked


# --------------------------------------------------------------------------
# checksums, signing, manifest
# --------------------------------------------------------------------------


def write_sha256sums(outdir: Path, entries: list[tuple[str, str]]) -> Path:
    """Write SHA256SUMS listing basenames only, in the given fixed order.

    Fixed (root-then-efi) order rather than sorting is deliberate: it makes
    the file byte-for-byte reproducible across runs given the same inputs,
    which is worth more here than alphabetical tidiness. Two-space
    separator is the shasum(1)/sha256sum(1) "binary mode" convention, so a
    plain `sha256sum -c SHA256SUMS` on any of these files works unmodified.
    """
    path = outdir / "SHA256SUMS"
    path.write_text("".join(f"{sha}  {name}\n" for name, sha in entries))
    return path


def _run_minisign(argv: list[str], cwd: Path) -> subprocess.CompletedProcess:
    try:
        # input="" closes stdin after zero bytes: if the secret key turns out
        # to be password-protected, minisign fails fast instead of hanging
        # forever waiting on a TTY that a build host does not have.
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, input="")
    except FileNotFoundError as exc:
        raise uki_slots.Fail(
            "minisign is not installed or not on PATH; install it or pass --no-sign"
        ) from exc


def sign_sha256sums(outdir: Path, sums_path: Path, key: Path) -> None:
    if not key.exists():
        raise uki_slots.Fail(f"{key}: minisign secret key not found (pass --sign-key or --no-sign)")
    result = _run_minisign(["minisign", "-S", "-s", str(key), "-m", sums_path.name], outdir)
    if result.returncode != 0:
        raise uki_slots.Fail(f"minisign -S failed (exit {result.returncode}): {result.stderr.strip()}")
    # Never print or persist the key PATH beyond this one basename — the
    # instruction is explicit that the secret key must not reach the log or
    # manifest.json in any more identifying form than "which key signed it".
    print(f"[make-payload] signed with {key.name}")


def verify_signature(outdir: Path, sums_path: Path) -> None:
    """Verify the signature we just produced, against the PINNED public key.

    "Signed but does not verify" is a class of bug that must be caught here,
    on the build host, not discovered by the first machine that tries to
    install this payload.
    """
    result = _run_minisign(["minisign", "-V", "-m", sums_path.name, "-P", RELEASE_PUBKEY], outdir)
    if result.returncode != 0:
        raise uki_slots.Fail(
            f"self-verification of the signature just produced FAILED "
            f"(exit {result.returncode}): {result.stderr.strip()} — a payload "
            "that cannot verify against its own pinned public key must never "
            "leave the build host"
        )
    print("[make-payload] self-verify OK against pinned release public key")


def write_manifest(
    outdir: Path,
    payload_version: str,
    arch: str,
    source_image: Path,
    files: list[tuple[str, int, str]],
    baked_partuuid: uuid.UUID,
) -> Path:
    """Write manifest.json.

    Deliberately NOT part of the signature chain: SHA256SUMS +
    SHA256SUMS.minisig are the only artifacts an installer is required to
    trust. manifest.json is convenience metadata a human or dashboard can
    read without re-deriving anything from the binaries — treat any value in
    it as informational, never as an integrity claim.
    """
    manifest = {
        "format": 1,
        "version": payload_version,
        "arch": arch,
        "created_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "files": [{"name": name, "size": size, "sha256": sha} for name, size, sha in files],
        # Provenance only — see copy_uki_template()'s docstring for why this
        # is expected to be rewritten by whatever stages the update.
        "uki_template_root_partuuid": str(baked_partuuid),
        "source_image": source_image.name,
        # source_image_sha256 is intentionally omitted: hashing the full
        # multi-GB raw image a second time (on top of the read already done
        # to extract slot A) buys little — the shipped artifacts already
        # carry their own verified sha256 in `files`, which is what actually
        # matters for installing this payload.
    }
    path = outdir / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    return path


# --------------------------------------------------------------------------
# misc
# --------------------------------------------------------------------------


def disk_usage_bytes(path: Path) -> int:
    """Actual bytes consumed on disk, as opposed to the file's apparent size.

    st_blocks is always counted in 512-byte units per POSIX stat(2),
    regardless of the filesystem's native block size. Windows has no
    st_blocks, but this tool's own contract is build-host-only
    (macOS/Linux), so that is not a concern here.
    """
    return os.stat(path).st_blocks * 512


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", type=Path, default=_APPLIANCE / "mkosi.output" / "duduclaw-os.raw",
                     help="whole-disk image built by mkosi (default: %(default)s)")
    ap.add_argument("--uki", type=Path, default=_APPLIANCE / "mkosi.output" / "duduclaw-os.efi",
                     help="standalone UKI mkosi emitted (default: %(default)s)")
    ap.add_argument("--version", default=None,
                     help="payload version to publish under; defaults to appliance/mkosi.version's "
                          "content. May differ from the image's baked version to stage a test "
                          "upgrade payload from an unchanged image.")
    ap.add_argument("--image-version", default=None,
                     help="the raw image's OWN baked version, used to validate slot A's factory "
                          "label (expected f'duduclaw-os_{image_version}'). Defaults to "
                          "appliance/mkosi.version's content (the Debian mkosi line's convention) "
                          "when omitted — pass this explicitly for a Yocto .wic input, whose "
                          "version lives in meta-duduclaw/conf/distro/include/"
                          "duduclaw-platform-version.inc instead, not appliance/mkosi.version.")
    ap.add_argument("--outdir", type=Path, default=_APPLIANCE / "mkosi.output" / "payload",
                     help="parent directory for the versioned payload subdirectory (default: %(default)s)")
    ap.add_argument("--sign-key", type=Path, default=Path.home() / ".minisign" / "duduclaw-os-release.key",
                     help="minisign secret key (default: %(default)s)")
    ap.add_argument("--no-sign", action="store_true", help="skip SHA256SUMS.minisig (dev/CI use only)")
    ap.add_argument("--force", action="store_true", help="overwrite an existing versioned output directory")
    args = ap.parse_args()

    raw_path = args.raw.expanduser()
    uki_path = args.uki.expanduser()
    outdir = args.outdir.expanduser()
    sign_key = args.sign_key.expanduser()

    if not raw_path.exists():
        raise uki_slots.Fail(f"{raw_path}: no such file (build the image first)")
    if not uki_path.exists():
        raise uki_slots.Fail(f"{uki_path}: no such file (build the image first)")

    if args.image_version is not None:
        image_version = args.image_version.strip()
        if not image_version:
            raise uki_slots.Fail("--image-version was given but empty")
    else:
        version_file = _APPLIANCE / "mkosi.version"
        image_version = version_file.read_text().strip()
        if not image_version:
            raise uki_slots.Fail(f"{version_file} is empty")
    payload_version = args.version or image_version

    final_dir = outdir / f"duduclaw-os_{payload_version}"
    if final_dir.exists():
        if not args.force:
            raise uki_slots.Fail(f"{final_dir} already exists; pass --force to overwrite")
        print(f"[make-payload] --force: removing existing {final_dir}")
        shutil.rmtree(final_dir)
    final_dir.mkdir(parents=True)

    print(f"[make-payload] reading GPT of {raw_path.name}")
    parts = uki_slots.read_gpt(raw_path)
    slot_a, slot_b = select_slots(parts)
    assert_slot_invariants(slot_a, slot_b, image_version)
    arch = uki_slots.GPT_ROOT_TYPES[slot_a.type_uuid]
    print(f"[make-payload] slot A: {slot_a}")
    print(f"[make-payload] slot B: {slot_b}")
    print(f"[make-payload] arch={arch} image_version={image_version} payload_version={payload_version}")

    root_path = final_dir / f"duduclaw-os_{payload_version}.root-{arch}.raw"
    efi_path = final_dir / f"duduclaw-os_{payload_version}.efi"

    slot_a_bytes = (slot_a.last_lba - slot_a.first_lba + 1) * uki_slots.SECTOR
    print(f"[make-payload] extracting slot A ({slot_a_bytes} bytes) -> {root_path.name}")
    root_size, root_sha = extract_root_payload(raw_path, slot_a, root_path)

    apparent = root_path.stat().st_size
    actual = disk_usage_bytes(root_path)
    print(
        f"[make-payload] {root_path.name}: apparent={apparent}B "
        f"actual-on-disk={actual}B (sparse savings: {apparent - actual}B, "
        f"{100 - actual * 100 // max(apparent, 1)}% reclaimed)"
    )

    print(f"[make-payload] copying UKI template -> {efi_path.name}")
    efi_size, efi_sha, baked_partuuid = copy_uki_template(uki_path, efi_path)
    print(
        f"[make-payload] UKI template bakes root=PARTUUID={baked_partuuid} "
        "(provenance only — the on-machine installer rewrites this before staging)"
    )

    sums_path = write_sha256sums(final_dir, [(root_path.name, root_sha), (efi_path.name, efi_sha)])
    print(f"[make-payload] wrote {sums_path.name}")

    if args.no_sign:
        print("[make-payload] --no-sign: skipping SHA256SUMS.minisig")
    else:
        sign_sha256sums(final_dir, sums_path, sign_key)
        verify_signature(final_dir, sums_path)

    manifest_path = write_manifest(
        final_dir, payload_version, arch, raw_path,
        [(root_path.name, root_size, root_sha), (efi_path.name, efi_size, efi_sha)],
        baked_partuuid,
    )
    print(f"[make-payload] wrote {manifest_path.name}")
    print(f"[make-payload] OK: {final_dir}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except uki_slots.Fail as e:
        print(f"[make-payload] FAIL: {e}", file=sys.stderr)
        sys.exit(1)
