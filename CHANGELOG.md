# Changelog

All notable changes to DuDuClaw OS are documented here. Versioning is
independent of the DuDuClaw platform (see the `VERSION` file) and follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-09-04 — first tagged bring-up release

First versioned release of DuDuClaw OS as a standalone repo. Marks the
bring-up milestone; not GA (see the README status note and the `VERSION`
file).

### Added
- Bootable Yocto appliance image (`duduclaw-image-appliance`) for
  `duduclaw-qemux86-64` and `duduclaw-genericx86-64`: A/B atomic update with
  rollback, read-only root, and the full DuDuClaw gateway + dashboard payload.
- Graphical live installer ISO (`duduclaw-image-live`) for both machines: boots
  a squashfs live root off USB/optical and writes the production A/B system to
  the target's internal disk. Published for `qemux86-64` (QEMU-boot-validated)
  and `genericx86-64` (real-hardware target). Fixes the live-root squashfs mount
  by enabling `CONFIG_SQUASHFS` through the canonical `cfg/fs/squashfs.scc`
  kernel feature (the prior bare `.cfg` fragment did not take effect).
- Security trust chain: self-signed Secure Boot (dual-signed per-slot UKI),
  read-only root with dm-verity block integrity, and TPM2/LUKS PCR 7+11 key
  sealing (fail-open path working; automatic enrollment is an open defect
  pending a real-hardware TPM).
- Cross-boot persistence of machine-id and the entropy seed under the
  read-only root.
- Independent OS release versioning: the repo-root `VERSION` file is the
  single source of truth for the release artifact name and GitHub Release
  tag, decoupled from the embedded platform version.
- `scripts/release-os.sh publish` — uploads the packaged image
  (`.wic.zst` + `.sha256` + `.minisig` + `manifest.json`) to a GitHub
  Release, re-verifying the signature and checksum fail-closed before any
  upload.
- Standalone-repo hygiene: README, this changelog, LICENSE, and `.gitignore`.

### Changed
- Split out of the main DuDuClaw repo (2026-09): `meta-duduclaw/`,
  `appliance/`, and `scripts/release-os.sh` moved into this repo; the Rust
  workspace stays in the platform repo and is vendored as a trimmed snapshot
  via `refresh-src.sh`.

### Notes
- `appliance/` (the earlier Debian/mkosi line) is frozen as a
  reference/transition artifact.
- Detailed bring-up history (the Y1–Y20 waves) is in the git log.
