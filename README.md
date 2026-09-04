# DuDuClaw OS

A Yocto-built Linux image that turns a small x86-64 box into a headless,
always-on appliance running [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw)
AI agents. Flash it, plug in power and ethernet, and the DuDuClaw dashboard
comes up on the LAN. The box has no screen, keyboard, or interactive install;
everything after first boot is done in the browser.

This repo holds the **base-OS line**: the `meta-duduclaw/` Yocto layer (distro
policy, machine configs, and recipes for the `duduclaw-*` binaries) plus the
`scripts/release-os.sh` build/sign/publish pipeline. It vendors a trimmed
snapshot of the DuDuClaw platform's Rust workspace, which lives in the separate
[DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) repo.

> **Status: bring-up (0.1.0, pre-GA).** The image boots, updates A/B with
> rollback, and the trust chain below is largely in place, but this is not a
> general-availability release. The `0.x` line tracks bring-up; `1.0.0` will
> mark the first GA.

## What's in the image

- **Yocto Project 6.0 "wrynose"** (LTS), default kernel Linux 6.18.
- Two machines: `duduclaw-qemux86-64` (the QEMU-bootable bring-up target) and
  `duduclaw-genericx86-64` (real x86-64 hardware).
- A/B atomic update with rollback, read-only root, and a full DuDuClaw gateway
  + dashboard payload.

## Security trust chain

- **Secure Boot** — self-signed PK/KEK/db, a dual-signed UKI per A/B slot,
  keys auto-enrolled on first boot.
- **Read-only root + dm-verity** — the rootfs is immutable and verified
  block-by-block; tampering fails the read, not just the boot.
- **TPM2 + LUKS (partial)** — PCR 7+11 measured-boot key sealing with a
  fail-open recovery path is wired; automatic enrollment is an open defect
  pending a real-hardware TPM (QEMU/swtpm cannot complete it).

## Build

Prerequisites:

- Docker — the Yocto build runs inside a `duduclaw-yocto-builder` container.
- A checkout of the [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) platform
  repo as a sibling directory. The OS vendors a snapshot of its Rust workspace;
  see `meta-duduclaw/recipes-duduclaw/duduclaw-cli/refresh-src.sh` (override the
  path with `DUDUCLAW_CLI_SRC_ROOT`).
- `minisign` and `gh` for signing and publishing releases.

```bash
./scripts/release-os.sh audit      # show OS + embedded-platform versions
./scripts/release-os.sh build      # kas build (inside the running builder)
./scripts/release-os.sh smoke      # headless QEMU boot to a login prompt
./scripts/release-os.sh package    # smoke-gate + compress + sha256 + minisign
./scripts/release-os.sh publish    # upload to a GitHub Release
```

Every subcommand's `v<version>` is optional and defaults to the `VERSION`
file — the OS's own release line, independent of the embedded platform
version. Run `release-os.sh` with no argument for the full usage text.

## Repo layout

| Path | What |
|---|---|
| `meta-duduclaw/` | the Yocto layer (distro, machines, images, `duduclaw-*` recipes) |
| `appliance/` | the earlier Debian/mkosi appliance line — **frozen**, kept as a reference/transition artifact; the product is not built from here |
| `scripts/release-os.sh` | the `build` → `smoke` → `package` → `publish` pipeline |
| `VERSION` | the OS's independent release version |

## License

Apache License 2.0 — the same license as the
[DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) platform. See [LICENSE](LICENSE).
