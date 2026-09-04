# DuDuClaw OS

<div align="center">

[繁體中文](README.md) · **English**

</div>

DuDuClaw OS is a Yocto-built Linux image that turns a small x86-64 box into an always-on appliance running [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) AI agents. Flash it, plug in power and ethernet, and the DuDuClaw dashboard comes up on the LAN; everything after that is done in the browser. The box needs no screen or keyboard, and there is no interactive install.

This repo is the **base-OS line**: the `meta-duduclaw/` Yocto layer (distro policy, machine configs, recipes for the `duduclaw-*` binaries) plus the `scripts/release-os.sh` build / sign / publish pipeline. The DuDuClaw platform's Rust workspace lives in its own repo and is vendored here as a trimmed snapshot.

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/zhixuli0406/DuDuClaw-OS/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

> **Status: bring-up (0.1.0, pre-GA).** The image boots, updates A/B with rollback, and the trust chain is largely in place, but this is not a general-availability release: the `0.x` line tracks bring-up, `1.0.0` will mark the first GA. All verification so far is under QEMU; **the image has not yet been booted on real x86-64 hardware**.

## Contents

- [Why DuDuClaw OS?](#why)
- [What's in the image](#whats-inside)
- [Trust chain](#trust)
- [Quick start: download, verify, flash](#quickstart)
- [Build from source](#build)
- [Repo layout](#layout)
- [Documentation](#docs)
- [License](#license)

<a id="why"></a>

## Why DuDuClaw OS?

Installing Linux yourself and then `duduclaw` on top works fine. Putting that box behind a counter, or handing it to a customer with no engineer, means you also own updates, rollback, tamper resistance, and first-time setup. DuDuClaw OS builds those into the image:

| Need | Your own Linux + duduclaw | DuDuClaw OS |
|---|---|---|
| First-time setup | SSH in and edit config | Auto-provisioned on first boot; the dashboard appears on the LAN |
| System updates | Package manager; you fix failures | A/B dual-slot atomic update, automatic rollback on boot failure |
| Tamper resistance | Roll your own | Read-only root + dm-verity block verification; modified data fails to read |
| Boot trust | Secure Boot usually turned off | Self-signed Secure Boot, a dual-signed UKI per slot, keys auto-enrolled on first boot |
| Disk keys | Manual LUKS | TPM2 PCR 7+11 sealing (partial, see below) |
| Desktop and apps | Install one by one | Own compositor/shell, Flatpak offline preload (Chromium, LibreOffice, Steam), Chinese IME |

<a id="whats-inside"></a>

## What's in the image

- **Yocto Project 6.0 "wrynose"** (LTS), default kernel Linux 6.18.
- Two machines: `duduclaw-qemux86-64` (the QEMU-bootable bring-up target) and `duduclaw-genericx86-64` (real x86-64 hardware, x86-64-v3 tune).
- Each release publishes two artifact forms per machine, each with a `.sha256` and a minisign `.minisig`:

| Artifact | Contents | Use |
|---|---|---|
| `duduclaw-os-<machine>-v<ver>.wic.zst` | `duduclaw-image-appliance`: A/B update chain + full desktop (compositor/shell, Chromium, LibreOffice, Steam, IME) | Whole-disk flash; the daily-driver box |
| `duduclaw-os-installer-<machine>-v<ver>.iso` | `duduclaw-image-live`: squashfs live environment + graphical installer that writes `duduclaw-image-ab` (headless gateway + dashboard) to the target's internal disk | Flash to USB, boot, install |

<a id="trust"></a>

## Trust chain

- **Secure Boot** — self-signed PK/KEK/db, a dual-signed UKI per A/B slot, keys auto-enrolled on first boot.
- **Read-only root + dm-verity** — the rootfs is immutable and verified block by block; tampering fails the read, not just the boot.
- **TPM2 + LUKS (partial)** — PCR 7+11 measured-boot key sealing with a fail-open recovery path is wired; automatic enrollment is an open defect pending a real-hardware TPM (QEMU/swtpm cannot complete it).
- **Signed release artifacts** — every file ships with a `.sha256` and a minisign `.minisig`; the public key is pinned in `scripts/release-os.sh` and re-verified fail-closed before upload. Vulnerability reporting: [SECURITY.md](SECURITY.md).

<a id="quickstart"></a>

## Quick start: download, verify, flash

Download the artifact plus its `.sha256` and `.minisig` from [GitHub Releases](https://github.com/zhixuli0406/DuDuClaw-OS/releases), and verify before flashing:

```bash
minisign -V -P RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n -m <file>
shasum -a 256 -c <file>.sha256
```

**Installer ISO (recommended for real hardware)**

```bash
dd if=<iso> of=/dev/<usb> bs=4M conv=fsync    # or balenaEtcher
```

Boot the target in UEFI mode with Secure Boot in setup mode or temporarily off (the first boot enrolls the DuDuClaw keys). Boot from the USB stick, pick the target SSD in the graphical installer, and reboot: the installed system is the A/B UKI + systemd-boot layout, and the dashboard is reachable from a browser on the same LAN.

**Whole-disk image (skips the installer)**

```bash
zstd -d <wic.zst>
dd if=<wic> of=/dev/<target-disk> bs=4M conv=fsync    # or bmaptool copy
```

> Both forms for `duduclaw-qemux86-64` are boot-verified under QEMU. `duduclaw-genericx86-64` is the real-hardware target and cannot be booted under QEMU; v0.1.0 has been config-audited only, and a real-hardware boot is the most important open validation item.

<a id="build"></a>

## Build from source

Prerequisites:

- Docker. The Yocto build runs inside a `duduclaw-yocto-builder` container (macOS has no native bitbake).
- A sibling checkout of the platform repo, needed only to refresh the vendored snapshots (`meta-duduclaw/recipes-duduclaw/duduclaw-cli/refresh-src.sh`; override the path with `DUDUCLAW_CLI_SRC_ROOT`).
- `minisign` and `gh` for signing and publishing.

```bash
./scripts/release-os.sh audit      # show OS + embedded-platform versions
./scripts/release-os.sh build      # kas build inside the running builder
./scripts/release-os.sh smoke      # headless QEMU boot to a login prompt
./scripts/release-os.sh package    # smoke gate + compress + sha256 + minisign
./scripts/release-os.sh publish    # upload to a GitHub Release
```

Every subcommand's `v<version>` is optional and defaults to the `VERSION` file, the OS's own release line, independent of the embedded platform version. Run `release-os.sh` with no argument for the full usage text. Builder container setup, cache and disk layout, and the role of each image recipe are in [`meta-duduclaw/README.md`](meta-duduclaw/README.md).

<a id="layout"></a>

## Repo layout

| Path | What |
|---|---|
| `meta-duduclaw/` | the Yocto layer (distro, machines, images, `duduclaw-*` recipes, kas configs) |
| `scripts/release-os.sh` | the `build → smoke → package → publish` pipeline |
| `VERSION` | the OS's independent release version |
| `docs/` | public docs, one subdir per type, indexed in `docs/README.md` |
| `wiki/` | internal bring-up notes, acceptance checklists, evidence logs |
| `appliance/` | the earlier Debian/mkosi appliance line, **frozen**, kept as a reference/transition artifact; the product is not built from here |

<a id="docs"></a>

## Documentation

- [`docs/README.md`](docs/README.md) — the documentation index for this repo (public docs, component references, internal notes, the placement rule).
- [`meta-duduclaw/README.md`](meta-duduclaw/README.md) — layer reference: layout, image roles, builder container, `kas build`.
- [`CHANGELOG.md`](CHANGELOG.md) — release history, Keep a Changelog format.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`SECURITY.md`](SECURITY.md) — how to contribute, how to report vulnerabilities.
- User-facing feature docs live in the platform repo: [DuDuClaw OS appliance](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/features/50-duduclaw-os-appliance.md), [hardware requirements](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/hardware-requirements.md), [app compatibility layer](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/app-compat.md).

<a id="license"></a>

## License

Apache License 2.0, the same license as the [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) platform. See [LICENSE](LICENSE).
