# DuDuClaw OS

<div align="center">

[繁體中文](README.md) · **English**

</div>

DuDuClaw OS is a Yocto-built Linux operating system in which the AI agent is a native resident: it turns an x86-64 box into a machine for [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) AI employees. It has a desktop of its own (an in-house Wayland compositor and shell, a lock screen, a first-run wizard, Cmd+K to hand work to the agent from anywhere), so a person and the AI share one machine without getting in each other's way: the agent's GUI work runs in a shadow workspace by default, and the moment you touch the keyboard or mouse, whatever it was driving on your desktop yields. The dashboard is served by the gateway, so the box is operable from a browser on the LAN with or without a screen.

This repo is the **base-OS line**: the `meta-duduclaw/` Yocto layer (distro policy, machine configs, recipes for the `duduclaw-*` binaries) plus the `scripts/release-os.sh` build / sign / publish pipeline. The DuDuClaw platform's Rust workspace lives in its own repo and is vendored here as a trimmed snapshot.

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/zhixuli0406/DuDuClaw-OS/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

> **Status: bring-up (0.1.0, pre-GA).** The image boots and updates A/B with rollback; the trust chain is wired in the layer but the published images do not yet enable signing / verity / TPM (see Trust chain). This is not a general-availability release: the `0.x` line tracks bring-up, `1.0.0` will mark the first GA. All verification so far is under QEMU; **the image has not yet been booted on real x86-64 hardware**.

## Contents

- [Why DuDuClaw OS?](#why)
- [What's in the image](#whats-inside)
- [Desktop environment](#desktop)
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
| Tamper resistance | Roll your own | Read-only root (desktop edition default); dm-verity block verification wired, enabled by a build overlay (not in v0.1.0) |
| Boot trust | Secure Boot usually turned off | Self-signed Secure Boot, a dual-signed UKI per slot, first-boot key enrollment — wired, enabled by a build overlay (v0.1.0 images are unsigned; boot with Secure Boot off) |
| Disk keys | Manual LUKS | TPM2 PCR 7+11 sealing (build overlay option, partial, not in v0.1.0) |
| Desktop and apps | Install one by one | Own compositor/shell, Flatpak offline preload (Chromium, LibreOffice, Steam), Chinese IME |
| One machine shared by a person and the AI | Separate windows, unaware of each other | Built-in delegation bar (Cmd+K); the agent's GUI work runs in a shadow workspace by default and never touches your windows or cursor; any input from you freezes an agent driving on your desktop |
| AI toolchain | `npm install -g` one vendor at a time, redone on every machine | Ten vendor CLIs in the image: `claude`, `codex`, `gemini`, `qwen`, `kimi`, `copilot`, `grok`, `agent` (Cursor), `opencode`, `vibe` — working at first boot, credentials on `/data` so an update never wipes them |
| Offline inference | Build llama.cpp yourself, write your own unit | llama.cpp `llama-server` in the image; weights downloaded from the dashboard into `/data/duduclaw/models`, so delegation keeps working with no network |

<a id="whats-inside"></a>

## What's in the image

- **Yocto Project 6.0 "wrynose"** (LTS), default kernel Linux 6.18.
- Two machines: `duduclaw-qemux86-64` (the QEMU-bootable bring-up target) and `duduclaw-genericx86-64` (real x86-64 hardware, x86-64-v3 tune).
- Each release publishes two artifact forms per machine, each with a `.sha256` and a minisign `.minisig`:

| Artifact | Contents | Use |
|---|---|---|
| `duduclaw-os-<machine>-v<ver>.wic.zst` | **Desktop edition** `duduclaw-image-appliance`: A/B update chain + desktop shell + Chromium / LibreOffice / Steam + IME + app compatibility layer + read-only root + firewall + login hardening | Whole-disk flash; the daily driver |
| `duduclaw-os-installer-<machine>-v<ver>.iso` | `duduclaw-image-live`: squashfs live environment + graphical installer. In v0.1.0 it writes the **base image** `duduclaw-image-ab`: the same A/B layout, desktop shell and gateway, without the app layer, compatibility layer, read-only root or firewall — a bring-up artifact | Flash to USB, boot, install |
| `duduclaw-os-installer-desktop-<machine>-v<ver>.iso` | `duduclaw-image-live-desktop`: the same installer, writing the desktop edition `duduclaw-image-appliance` (added to v0.1.0 on 2026-09-04) | Flash to USB, boot, install; yields the same desktop edition as the whole-disk image |

<a id="desktop"></a>

## Desktop environment

Every DuDuClaw OS image boots straight into its own desktop, fully operable from the keyboard (the desktop edition adds the app layer and shipping hardening, see the table above):

- **In-house compositor and shell** — `duduclaw-comp` (Wayland compositor) + `duduclaw-shell` (the desktop shell): home screen, window switcher, lock screen, control center; Cmd+K summons the delegation bar over any app to hand work to an AI employee. The full shortcut list is in the platform repo: [OS keyboard shortcuts](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/features/51-os-keyboard-shortcuts.md).
- **First-run wizard** — language, account, theme and Wi-Fi are set in a graphical wizard on first boot; the installer ISO is a graphical wizard too (pick disk, confirm, write progress, reboot).
- **Input and audio** — fcitx5 Chinese IME, PipeWire / WirePlumber audio, XWayland for X11 apps.
- **Shared without getting in your way** — the agent has its own input seat; GUI tasks run on a headless shadow output by default (with an optional picture-in-picture preview) and never touch your windows, focus or cursor; human input always wins, with the compositor freezing an agent driving on your desktop (3–4 ms measured under QEMU); Super+Enter hands back, Super+Esc is the emergency stop; co-driving is off by default, consequential actions are approved first, and logins / payments are always handed to you. Full write-up in the platform repo: [Desktop edition](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/features/52-desktop-edition.md).
- **AI toolchain in the image** (desktop edition) — ten vendor coding CLIs bundled under `/opt/duduclaw/runtimes`, with `claude`, `codex`, `gemini`, `qwen`, `kimi`, `copilot`, `grok`, `agent`, `opencode` and `vibe` on `PATH` at first boot. Credentials all land in `/data/duduclaw` (mode 0700), so a system update never wipes them. Local inference runs on llama.cpp's `llama-server`; no model weights ship in the image — the dashboard downloads one into `/data/duduclaw/models`. What is deliberately *not* bundled, and how to regenerate the payload: [AI runtimes guide](docs/guides/ai-runtimes.md).
- **Apps** (desktop edition) — Flatpak offline preload of Chromium, LibreOffice and Steam. The app compatibility layer is declared through `compat.d`: Bottles for Windows desktop apps, a KVM virtual machine + RDP for full Windows, Waydroid for Android (no GApps, self-setup); macOS apps are not run locally. Scope and the explicit non-promises are in the [app compatibility guide](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/app-compat.md).

The base image the v0.1.0 installer ISO writes (`duduclaw-image-ab`) has the same desktop shell and gateway, just without the app layer; the dashboard is served by the gateway, so the box is operable from a browser on the LAN with or without a screen. What the desktop itself does with no monitor attached (whether it falls back to a purely headless box) has not been defined on real hardware yet; it is a bring-up open item.

<a id="trust"></a>

## Trust chain

The layer wires the whole chain, but the v0.1.0 images enable only part of it. Shipped: **A/B atomic update with rollback** and a **read-only root** (desktop edition). The three items below are build-time overlay options that the **v0.1.0 artifacts do not enable** (verified by opening the published wic: both slot UKIs and systemd-boot carry no signature, the GPT has no verity partition, no TPM packages are installed):

- **Secure Boot + dm-verity** (`kas/sb-signing.yml`) — self-signed PK/KEK/db, a dual-signed UKI per slot, first-boot key enrollment; the rootfs verified block by block, so tampering fails the read.
- **TPM2 + LUKS** (`kas/tpm-luks.yml`, partial) — PCR 7+11 measured-boot key sealing with a fail-open recovery path is wired; automatic enrollment is an open defect pending a real-hardware TPM (QEMU/swtpm cannot complete it).
- **Signed release artifacts** (enabled) — every file ships with a `.sha256` and a minisign `.minisig`; the public key is pinned in `scripts/release-os.sh` and re-verified fail-closed before upload. Vulnerability reporting: [SECURITY.md](SECURITY.md).

`scripts/release-os.sh build` currently uses the base kas config only; producing signed images means building with the overlays, which is on the list for the next release.

<a id="quickstart"></a>

## Quick start: download, verify, flash

Download the artifact plus its `.sha256` and `.minisig` from [GitHub Releases](https://github.com/zhixuli0406/DuDuClaw-OS/releases), and verify before flashing:

```bash
minisign -V -P RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n -m <file>
shasum -a 256 -c <file>.sha256
```

**Installer ISO: `installer-desktop` = desktop edition; `installer` = base image (desktop shell + gateway, no app layer)**

```bash
dd if=<iso> of=/dev/<usb> bs=4M conv=fsync    # or balenaEtcher
```

Boot the target in UEFI mode with **Secure Boot off** (the v0.1.0 images are unsigned; only signed builds enroll the DuDuClaw keys on first boot). Boot from the USB stick, pick the target SSD in the graphical installer, and reboot: the installed system is the A/B UKI + systemd-boot layout, and the dashboard is reachable from a browser on the same LAN.

**Whole-disk image (desktop edition: desktop + apps + shipping hardening)**

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
