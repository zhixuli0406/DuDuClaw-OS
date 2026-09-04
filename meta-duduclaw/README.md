# meta-duduclaw — DuDuClaw OS Yocto layer

The product layer of DuDuClaw OS: distro policy, the two machine
definitions, the image recipes, and the recipes that build the `duduclaw-*`
Rust binaries from vendored snapshots of the
[DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) platform workspace. The
repo-root [`README.md`](../README.md) is the product overview; this file is
the layer's reference: what is in it and how to build it.

The dated bring-up narrative that used to live in this file (why each
decision was made, the bugs hit on the way, verification transcripts) is
archived unchanged in
[`wiki/impl/meta-duduclaw-bring-up-notes-2026-08.md`](../wiki/impl/meta-duduclaw-bring-up-notes-2026-08.md);
the raw boot/build transcripts are under
[`wiki/reports/bring-up-evidence/`](../wiki/reports/bring-up-evidence/).
Release-by-release status is in the repo-root [`CHANGELOG.md`](../CHANGELOG.md).

## Target release

Yocto Project **6.0 "wrynose"** (LTS, supported to 2028-04); kernel
`linux-yocto` **6.18**. Upstream is pinned as three separate repos —
bitbake, openembedded-core, meta-yocto — at exact commits in
`kas/duduclaw-os.yml`. There is deliberately no `poky` checkout: for this
release the `poky` repo carries no `wrynose-*` tag, and its similarly named
legacy tags are unrelated ~2012 releases (the dead end is written up in the
bring-up notes, "Why three repos, not one poky checkout").

kas drives the build: one YAML pins every upstream commit, declares the
layer set, and carries the build-time `local.conf` lines, so there is no
hand-maintained `bblayers.conf` and no `oe-init-build-env` ritual.
`kas build` / `kas shell` are the only commands needed.

## Layer layout

```
meta-duduclaw/
├── conf/
│   ├── layer.conf
│   ├── distro/duduclaw-os.conf              # INIT_MANAGER=systemd, EFI + systemd-boot, UKI
│   │   └── include/duduclaw-platform-version.inc   # embedded platform version — NOT the OS
│   │                                          # release version (that is the repo-root VERSION file)
│   └── machine/
│       ├── duduclaw-qemux86-64.conf         # QEMU bring-up / test machine (KMACHINE=qemux86-64)
│       └── duduclaw-genericx86-64.conf      # real x86-64 hardware, x86-64-v3 tune, i915/amdgpu firmware
├── classes/                                 # duduclaw-{secure-boot,ab-dualsign-uki,verity,tpm,rescue-boot,
│                                            #   ab-partflags,data-partflags}.bbclass
├── recipes-core/
│   ├── images/                              # image recipes + shared .inc payload sets (see "Images")
│   ├── initrdscripts/ os-release/ systemd/
├── recipes-duduclaw/                        # duduclaw-cli / -sysd / -comp / -shell: vendored *-src/ snapshot
│                                            #   + refresh-src.sh each; plus OS glue recipes: ab-update,
│                                            #   firstboot, data-binds, data-open, persist-seed, firewall,
│                                            #   journald, secaudit-scan, rescue, os-installer, live-tweaks,
│                                            #   flatpak-offline-repo, flatpak-kiosk-verify, polkit-flatpak,
│                                            #   compat-runners, steam-devices
├── recipes-kernel/linux/                    # linux-yocto 6.18 bbappend + per-machine config fragments
├── recipes-graphics/mesa/                   # Mesa version pin (LLVM codegen fix for the GUI stack)
├── recipes-multimedia/pipewire/             # PipeWire / WirePlumber audio backend wiring
├── recipes-connectivity/duduclaw-network-config/
├── recipes-support/                         # fcitx5, fcitx5-chewing, libchewing, extra-cmake-modules, sbsigntool
├── recipes-security/gitleaks/
├── recipes-waydroid/                        # waydroid, libgbinder, libglibutil, python3-gbinder
├── files/wic/                               # .wks.in partition layouts (single-root, +/data, A/B)
├── kas/
│   ├── duduclaw-os.yml                      # base build config (qemux86-64) — start here
│   ├── duduclaw-os-genericx86-64.yml        # real-hardware machine config
│   ├── sb-signing.yml                       # Secure Boot signing overlay (mounts repo-root sb-keys/)
│   ├── tpm-luks.yml                         # TPM2 + LUKS overlay (pins meta-security / meta-tpm)
│   └── serial1.yml                          # release overlay: -j1 serial build (OOM guard), SPDX off
├── docker/Dockerfile.yocto-builder          # Linux build container for macOS hosts
└── scripts/sb-keygen.sh                     # self-signed PK/KEK/db generation
```

## Images

| Recipe | What it is | Role |
|---|---|---|
| `duduclaw-image-appliance` | A/B update chain + full desktop payload (own compositor/shell, Flatpak-preloaded Chromium / LibreOffice / Steam, fcitx5 IME), shipping hardening | **Shipping image** — the `.wic.zst` in each release |
| `duduclaw-image-appliance-test` | Same payload, root serial autologin | QEMU test variant, never shipped |
| `duduclaw-image-ab` | A/B GPT layout + update chain, headless gateway + dashboard | Install payload embedded in the live installer |
| `duduclaw-image-live` (+ `-live-initramfs`) | squashfs live environment with the graphical installer, writes `duduclaw-image-ab` to the target disk | The `.iso` in each release |
| `duduclaw-image-flatpak` | Flatpak / bubblewrap / ostree / polkit carriage on top of `-data` | Building block |
| `duduclaw-image-data` | `/data` partition + first-boot provisioning on top of `duduclaw-image` | Building block |
| `duduclaw-image` | `duduclaw-sysd` + `duduclaw` payload on top of `-minimal` | Building block |
| `duduclaw-image-minimal` | Console-only UKI + systemd-boot image | Bring-up / smoke |

Shared payload sets: `duduclaw-image-{data,flatpak,desktop,compat}.inc`;
read-only root + dm-verity wiring: `duduclaw-ro-root.inc`.

## Usage

The release pipeline (`scripts/release-os.sh build / smoke / package /
publish`, see the repo-root README) wraps everything below with builder
concurrency guards and the `serial1.yml` overlay. The manual steps are for
development and debugging.

### Host prerequisites

The reference dev host is macOS on Apple Silicon; any Linux host with Docker
works the same way with the platform flag dropped.

- **Docker Desktop with a large VM disk and ≥ 12 GB RAM.** A cold build of
  the appliance image peaks around 30 GB in `TMPDIR` on top of the
  download and sstate caches; the reference host runs an ~89 GB VM disk and
  still has to prune between multi-image builds.
- **A case-sensitive filesystem for `DL_DIR` / `SSTATE_DIR`.** bitbake
  refuses a case-insensitive `TMPDIR`, and macOS APFS bind mounts are
  case-insensitive by default. The reference host uses a dedicated volume:
  `diskutil apfs addVolume disk3 "Case-sensitive APFS" DuDuClawYoctoCache`
  (mounted at `/Volumes/DuDuClawYoctoCache`).
- **A Docker named volume for `TMPDIR`** (`docker volume create
  duduclaw-yocto-tmpdir`). `TMPDIR` on a virtiofs bind mount was observed
  to lose writes under concurrent workers; the caches are fine on the bind
  mount because their access pattern is fetch-once / read-much-later.
- **Run bitbake as the container's non-root `yocto` user (uid 1000).**
  OE-core refuses to run as root. Rebuild the builder image after editing
  the Dockerfile instead of patching a running container: a `useradd`
  applied live evaporates on the next container recreate and then trips
  `do_package_qa`'s `host-user-contaminated` check as a false positive.
  Check with `docker exec -u 1000 duduclaw-yocto id` → `uid=1000(yocto)
  gid=1000(yocto)`.

The full story behind each item is in the bring-up notes, "磁碟策略".

### Builder container

```bash
docker build --platform linux/arm64 \
    -f meta-duduclaw/docker/Dockerfile.yocto-builder \
    -t duduclaw-yocto-builder \
    meta-duduclaw/docker

docker run -d --name duduclaw-yocto --platform linux/arm64 \
    -v "$(git rev-parse --show-toplevel)":/workspace \
    -v /Volumes/DuDuClawYoctoCache:/yocto-cache \
    -v duduclaw-yocto-tmpdir:/yocto-vmfs \
    -w /workspace \
    duduclaw-yocto-builder -c "sleep infinity"
```

The container is long-lived; `release-os.sh` only `exec`s into one that is
already up and refuses to start a build while another kas/bitbake process
is in flight.

### Build

```bash
# qemux86-64, image selected via KAS_TARGET (the kas file's own target: field is not the source of truth)
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && KAS_TARGET=duduclaw-image-appliance kas build meta-duduclaw/kas/duduclaw-os.yml"

# real hardware
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && KAS_TARGET=duduclaw-image-appliance kas build meta-duduclaw/kas/duduclaw-os-genericx86-64.yml"
```

Do not run two kas configs concurrently in one build dir: they rewrite the
same `build/conf/local.conf` and bitbake fails with cascading
"metadata not deterministic" errors.

### Boot under QEMU

OVMF (UEFI firmware for QEMU) is a host-side tool the image does not depend
on; build it once:

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml -c 'bitbake ovmf'"
```

Headless serial boot (`slirp` because an unprivileged container has no
`/dev/net/tun`):

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml -c \
     'runqemu duduclaw-image-appliance nographic serial wic ovmf slirp'"
```

`duduclaw-genericx86-64` cannot be booted this way (`runqemu` has no
support for it); real-hardware validation is a separate, still-open step.

Interactive bitbake shell for ad-hoc debugging:

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml"
```

### Secure Boot keys

`scripts/sb-keygen.sh` generates the self-signed PK/KEK/db chain into
`~/.duduclaw-sb/`. Copy the signing pair to the repo-root `sb-keys/`
(gitignored) and add the `kas/sb-signing.yml` overlay so the builder can
sign the UKIs. Key material must never be committed.

## Machine-name aliasing gotchas

Two separate checks stand between a custom machine name and a booting
kernel; both are handled in this layer but bite anyone adding a machine:

- `linux-yocto_6.18.bb` hardcodes `COMPATIBLE_MACHINE` as an anchored regex
  of upstream machine names. A custom name fails it even when the machine
  `require`s `qemux86-64.conf`, because the check is a textual `MACHINE`
  match. `recipes-kernel/linux/linux-yocto_6.18.bbappend` extends the regex
  for both machines.
- Passing that is not enough: `kernel-yocto.bbclass` looks up the BSP
  definition by `KMACHINE` (defaults to `${MACHINE}`) and fails with
  "Could not locate BSP definition". `KMACHINE = "qemux86-64"` in the QEMU
  machine config reuses the upstream BSP metadata; the real-hardware machine
  sets `KMACHINE = "common-pc-64"`.

## Status

See the repo-root [`CHANGELOG.md`](../CHANGELOG.md). v0.1.0 (2026-09-04) is
the first tagged bring-up release: both machines × both artifact forms are
published and signed; the QEMU machine is boot-verified for both forms, the
real-hardware machine is config-audited only.
