# meta-duduclaw — DuDuClaw OS Yocto layer

DuDuClaw OS's product layer: distro policy, machine definitions, and (from
Y1-2 onward) recipes for the five `duduclaw-*` Rust binaries. Lives in the
**main repo root** — not a separate repo, not under `commercial/` — per
[`commercial/docs/MAP-agent-native-os-2026-08.md`](../commercial/docs/MAP-agent-native-os-2026-08.md)
decision ⑥ "同版同發＝單 repo＋OS 進主版本流".

This is the **base-OS bring-up line** (Yocto), replacing the Debian
`appliance/` line for the eventual product image. `appliance/` is frozen
(map decision ⑤) as a reference/transition artifact — do not edit it as
part of this line's work.

## Target release

Yocto Project **6.0 "wrynose"**, current LTS as of 2026-08 (supported to
2028-04). Its own default kernel is already **Linux 6.18** — the exact LTS
`research/native-os-2026-08/kernel-self-maintain-2026-08.md` independently
recommended, so bring-up needed no separate kernel-version fight.

## Why three repos, not one "poky" checkout

A real dead end hit during Y1-1 bring-up, worth reading before touching the
pin in `kas/duduclaw-os.yml`: `git.yoctoproject.org/poky` has tags shaped
like `edison-6.0.2`, but `edison` is poky's own internal release-counter
codename from a completely unrelated ~2012-era release — checking it out
and grepping it found zero `uki.bbclass`, zero wic tooling, and the wrong
`meta-yocto` layout, all because the checkout was 14 years stale, not
because Yocto 6.0 lacks these features. No `wrynose-*` tag exists on that
repo at all.

The real release artifacts, per
`https://downloads.yoctoproject.org/releases/yocto/yocto-6.0.2/`, are three
separate repos pinned to exact commits (see `kas/duduclaw-os.yml` header
comment for the full citation trail):

| repo | url | pinned commit |
|---|---|---|
| bitbake | `git.openembedded.org/bitbake` | `acfe02fa38b5da9e6a36c6cedcf91d4fcbefbfbd` |
| openembedded-core | `git.openembedded.org/openembedded-core` | `5d1aa5c806c061a2994f4decb59016610f093213` |
| meta-yocto | `git.yoctoproject.org/meta-yocto` | `24c24cef5d1523fefe43a3e3d34667b37ae551f3` |

`meta-yocto` still contains `meta-poky/` and `meta-yocto-bsp/` as
subdirectories — same two layers Yocto has shipped for years, just no
longer bundled into a "poky" super-repo for this release.

## Why kas

Task called for "kas 或 repo 管理設定（選最簡）". kas wins: one declarative
YAML pins every upstream repo's exact commit, declares the layer set, and
carries build-time local.conf lines — no hand-maintained `bblayers.conf`,
no `oe-init-build-env` ritual to remember per shell. `kas checkout` /
`kas build` / `kas shell` are the only three commands anyone needs.

## Layer layout

```
meta-duduclaw/
├── conf/
│   ├── layer.conf
│   ├── distro/duduclaw-os.conf          # INIT_MANAGER=systemd, EFI+systemd-boot
│   └── machine/
│       ├── duduclaw-qemux86-64.conf     # QEMU dev/test machine (Y1-1 verified)
│       └── duduclaw-genericx86-64.conf  # real-HW target (N305/8845HS), DEFAULTTUNE
│                                         # pinned to x86-64-v3 (Y2-3), KMACHINE=
│                                         # common-pc-64, kernel fragments applied
├── recipes-core/images/
│   ├── duduclaw-image-minimal.bb        # console-only bring-up image, UKI+systemd-boot
│   ├── duduclaw-image.bb                # + duduclaw-sysd/duduclaw-cli/duduclaw-comp/
│   │                                     # duduclaw-shell payload — "開機即殼" (Y3-1/Y4-0):
│   │                                     # qemux86-64 boots straight into duduclaw-kiosk.
│   │                                     # service (comp+shell), real DRM/udev backend,
│   │                                     # real Wayland socket in /run/duduclaw-kiosk/
│   │                                     # (Y4-0 QEMU-verified after the libegl-mesa fix
│   │                                     # below — before that fix, comp always panicked
│   │                                     # on missing libEGL.so.1 and the kiosk service
│   │                                     # crash-looped to a permanent StartLimitBurst
│   │                                     # failure)
│   └── duduclaw-image-flatpak.bb        # + flatpak/bubblewrap/ostree/polkit chain (Y3-2,
│                                         # Y4-0 PASS: duduclaw-flatpak-kiosk-verify.service
│                                         # OVERALL PASS — real Flathub install of Chromium
│                                         # + 6 runtimes, --kiosk --dump-dom against the
│                                         # real gateway dashboard returns real DOM content)
├── recipes-kernel/linux/
│   ├── linux-yocto_6.18.bbappend        # COMPATIBLE_MACHINE alias fix (both machines)
│   └── linux-yocto/                     # duduclaw-{n305,8845hs,gaming}.cfg driver
│                                         # fragments, real-HW only, Y2-2 written / Y2-3
│                                         # build-verified via kernel_configme
├── recipes-duduclaw/                    # all five duduclaw-* binaries now build-verified:
│                                         # duduclaw-sysd/duduclaw-cli (Y2-1/Y2-3),
│                                         # duduclaw-comp/duduclaw-shell (Y4-0, first-ever
│                                         # successful build — see duduclaw-shell's own
│                                         # gen-git-manifests.sh header comment for the
│                                         # zed-monorepo workspace-inheritance fix this
│                                         # needed). duduclaw-cli-worker still has no
│                                         # recipe (zero work done on it).
├── kas/
│   ├── duduclaw-os.yml                  # build config — start here (qemux86-64)
│   └── duduclaw-os-genericx86-64.yml    # overlay for the real-HW machine (Y2-2/Y2-3)
├── docker/Dockerfile.yocto-builder      # Linux build container for macOS hosts
└── scripts/                             # (reserved)
```

## UKI 接通紀錄 (how the UKI + systemd-boot chain was actually verified)

`uki.bbclass` (`meta/classes-recipe/uki.bbclass` at the pinned oe-core
commit) is real and current — its own header comment documents the exact
distro/machine/image config needed. The config in this layer is lifted
**verbatim** from oe-core's own CI selftest for this precise scenario
(`meta/lib/oeqa/selftest/cases/uki.py::UkiTest.test_uki_boot_systemd`,
`core-image-minimal` + UEFI/OVMF + systemd-boot + QEMU x86_64), not guessed:

- Distro (`duduclaw-os.conf`): `INIT_MANAGER = "systemd"`,
  `EFI_PROVIDER = "systemd-boot"`,
  `PREFERRED_PROVIDER_virtual/bootloader = "systemd-boot"`.
- Machine (`duduclaw-qemux86-64.conf`): `MACHINE_FEATURES:append = " efi"`
  (qemux86-64's stock feature set is just `"x86 pci"` — efi is not on by
  default), `QB_KERNEL_ROOT = ""`, `QB_DEFAULT_KERNEL = "none"` (the kernel
  lives inside the signed UKI, not loaded separately by runqemu),
  `QEMU_USE_KVM = ""` (the selftest itself disables KVM with the comment
  "breaks boot" — moot here anyway since the Apple Silicon Docker Desktop
  host has no x86 KVM to offer).
- Image (`duduclaw-image-minimal.bb`): `require core-image-minimal.bb`,
  `IMAGE_FSTYPES:append = " wic"`, `WKS_FILE = "efi-uki-bootdisk.wks.in"`
  (found at `meta/files/wic/efi-uki-bootdisk.wks.in` — not `meta/wic/`,
  another path that moved since older Yocto docs/tutorials were written),
  `INITRAMFS_IMAGE = "core-image-minimal-initramfs"`,
  `IMAGE_CLASSES:append = " uki"`, `UKI_CMDLINE = "rootwait root=LABEL=root
  console=${KERNEL_CONSOLE}"`.

### COMPATIBLE_MACHINE alias gotcha

`linux-yocto_6.18.bb` hardcodes `COMPATIBLE_MACHINE` as a single anchored
regex literal listing exact upstream qemu machine names
(`^(qemuarm|...|qemux86-64|...)$`) — a custom machine name like
`duduclaw-qemux86-64` fails that regex even though it `require`s
`qemux86-64.conf`, because the check is a textual `MACHINE` match, not
something that flows through the require chain. First `bitbake -e
duduclaw-image-minimal` failed with "Nothing PROVIDES 'virtual/kernel'"
until `recipes-kernel/linux/linux-yocto_6.18.bbappend` extended the regex
via `COMPATIBLE_MACHINE:append = "|^duduclaw-qemux86-64$"`. The equivalent
fix for `duduclaw-genericx86-64` (real hardware) is **not yet done** — real
hardware doesn't use `linux-yocto_6.18.bb`'s qemu-only compat list at all,
it needs its own kernel provider story; tracked in
`commercial/docs/TODO-agent-first-os-2026-08.md` Y1 row.

**Getting past COMPATIBLE_MACHINE is not sufficient on its own** — once the
recipe accepts the machine, `kernel-yocto.bbclass`'s BSP-definition lookup
uses a *separate* variable, `KMACHINE` (defaults to `${MACHINE}`), and fails
with "Could not locate BSP definition for duduclaw-qemux86-64/standard" if
left unset. Fix: `KMACHINE = "qemux86-64"` in `duduclaw-qemux86-64.conf`,
reusing the upstream BSP metadata verbatim — this is the standard mechanism
for aliasing a custom machine name to an existing kernel BSP, not a hack.

## 磁碟策略 (disk strategy)

Two disk constraints collided during bring-up, both host-specific to this
macOS/Apple-Silicon dev machine, not anything the layer itself assumes:

1. **Docker Desktop's own VM disk is small.** `docker run --rm alpine df -h`
   showed only ~17GB free inside the VM's own ~58GB virtual disk at
   bring-up time — far short of the 50-100GB a cold Yocto build can eat.
   Fix: bind-mount the big directories (`DL_DIR`, `SSTATE_DIR`, `TMPDIR`)
   from the HOST filesystem instead of leaving them on the container's own
   layer — bind mounts don't consume the VM's own disk quota, only the
   host's. This repo's `appliance/` line already established this pattern
   (`Dockerfile.mkosi-runner` + `-v host:container` in `build.sh`); this
   layer follows the same convention.

2. **TMPDIR must be on a case-sensitive filesystem, and macOS APFS bind
   mounts default to case-insensitive.** `bitbake -e` failed with `"The
   TMPDIR (...) can't be on a case-insensitive file system"` the first time
   the cache dir was bind-mounted from a normal `appliance/.yocto-cache/`
   path. Fix: created a dedicated case-sensitive APFS volume sharing the
   same container's free-space pool (no fixed-size partition, no data
   copy):
   ```
   diskutil apfs addVolume disk3 "Case-sensitive APFS" DuDuClawYoctoCache
   ```
   mounted automatically at `/Volumes/DuDuClawYoctoCache`, bind-mounted
   into the builder container at `/yocto-cache`. This is the same class of
   trap as the `target/` APFS case-sensitivity issue previously hit on
   Rust builds on this machine — same fix shape, different mount point.
   The volume can be deleted with `diskutil apfs deleteVolume
   DuDuClawYoctoCache` if reclaiming it is ever needed; it shares disk3's
   free pool so it costs nothing while empty.

3. **bitbake refuses to run as root.** OE-core's sanity checker hard-fails
   with "Do not use Bitbake as root" — the builder Dockerfile creates a
   non-root `yocto` user (uid 1000) and `USER yocto` for exactly this
   reason; run `docker exec -u 1000 ...` (or rely on the Dockerfile's
   default `USER yocto`) rather than the container's default root shell.
   **Corollary that actually bit us**: if you patch a *running* container
   with `useradd` instead of rebuilding the image, the fix evaporates the
   next time the container is recreated — `/etc/passwd` has no entry for
   uid 1000, so `docker exec -u 1000` silently resolves its group to
   `gid=0(root)`, which collides with kernel headers' intentional
   `root:root` ownership and trips bitbake's `do_package_qa`
   `host-user-contaminated` check as a false positive, failing the whole
   build. Always `docker build` the image after editing the Dockerfile;
   verify with `docker exec -u 1000 <container> id` — it must print
   `uid=1000(yocto) gid=1000(yocto)`, not `gid=0(root)`.

4. **TMPDIR on a virtiofs bind mount can silently corrupt writes under
   concurrent workers.** Two different native recipes
   (`texinfo-dummy-native`, then `quilt-native`→`gnu-config-native`) each
   failed with a downstream consumer getting "No such file or directory"
   reading a file an *earlier* task had already reported as successfully
   populated — a write-then-read visibility gap. Retrying the exact failed
   task in isolation passed immediately; lowering `PARALLEL_MAKE`/
   `BB_NUMBER_THREADS` did **not** stop a second, different recipe from
   hitting the same class of failure on the next attempt, ruling out "just
   a parallelism race." Fix: put TMPDIR on a **Docker named volume**
   (backed by the Docker Desktop VM's own native filesystem, no virtiofs
   translation) instead of the case-sensitive APFS bind mount — `DL_DIR`/
   `SSTATE_DIR` stay on the host bind mount (fetch-once / populate-then-
   read-much-later access patterns never hit this). Trade-off: the Docker
   Desktop VM's own disk is much smaller than the host's (~59GB vs.
   hundreds of GB) — see "建置耗時與磁碟實耗" in the TODO doc for how tight
   this got and how it was managed (periodic `rm -rf` of TMPDIR, relying on
   SSTATE_DIR for fast catch-up — a standard, sanctioned Yocto pattern for
   disk-constrained build agents, not a hack).

## Usage

Build the Linux build container (macOS has no native bitbake support —
pseudo/fakeroot and various build steps assume Linux syscalls):

```bash
docker build --platform linux/arm64 \
    -f meta-duduclaw/docker/Dockerfile.yocto-builder \
    -t duduclaw-yocto-builder \
    meta-duduclaw/docker
```

Start a long-lived builder container, bind-mounting the repo, a
case-sensitive cache volume for DL_DIR/SSTATE_DIR (create one per "磁碟策略"
point 2 above if you don't have one yet), and a Docker named volume for
TMPDIR (point 4 — created once with `docker volume create
duduclaw-yocto-tmpdir`, no extra setup needed after that):

```bash
docker run -d --name duduclaw-yocto --platform linux/arm64 \
    -v "$(git rev-parse --show-toplevel)":/workspace \
    -v /Volumes/DuDuClawYoctoCache:/yocto-cache \
    -v duduclaw-yocto-tmpdir:/yocto-vmfs \
    -w /workspace \
    duduclaw-yocto-builder -c "sleep infinity"
```

Build (checkout + bitbake in one step; the Y1-1 bring-up took ~2h45m on a
cold-ish cache — 4 vCPU / 12GB Docker Desktop VM — dominated by `llvm-native`,
a transitive dependency of `systemd`'s `efi` PACKAGECONFIG needed to produce
`systemd-boot`'s EFI PE stub):

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas build meta-duduclaw/kas/duduclaw-os.yml"
```

OVMF (UEFI firmware for QEMU) is a separate host-side tool the image recipe
does NOT depend on — build it once before the first boot test (matches
oe-core's own CI selftest, which builds `image + " ovmf"` together):

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml -c 'bitbake ovmf'"
```

Boot the result under QEMU/OVMF (headless serial console — this is the
Y1-1 PASS criterion, a login prompt on serial, not a GTK window). `slirp`
is required inside an unprivileged container — the default tap networking
needs `/dev/net/tun`, which `docker run` doesn't grant by default and this
milestone doesn't need real networking for anyway:

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml -c \
     'runqemu duduclaw-image-minimal nographic serial wic ovmf slirp'"
```

Verified 2026-08-25 — full serial console evidence in
`meta-duduclaw/qemu-boot-y1-1-PASS-evidence-2026-08-25.log`:
`Welcome to DuDuClaw OS 0.1.0-y1-bringup (y1-bringup)!` → systemd boots to
`Multi-User System` → `Started Serial Getty on ttyS0` →
**`duduclaw-qemux86-64 login:`**.

Interactive bitbake shell for ad-hoc debugging:

```bash
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && kas shell meta-duduclaw/kas/duduclaw-os.yml"
```

## Status

See `commercial/docs/TODO-agent-first-os-2026-08.md` "Y 線" section for the
live status (build/boot evidence, disk/time actuals, what's deferred to
Y1-2).

As of Y4-0 (2026-08-26): `bitbake duduclaw-image-flatpak` builds 100% green
(all 7734 tasks succeed) and boots to a real "開機即殼" — `duduclaw-comp` +
`duduclaw-shell` run under `duduclaw-kiosk.service` with a real udev/DRM
backend and a real Wayland socket in `/run/duduclaw-kiosk/`, and
`duduclaw-flatpak-kiosk-verify.service` proves the Flatpak/Chromium chain
end-to-end (real Flathub network install, real `--kiosk --dump-dom` against
the real gateway dashboard). This took six real bugs to get here — see the
TODO doc's "Y4-0 本輪紀錄" section for the full list (a Yocto Rust version
gap, a zed-monorepo Cargo workspace-inheritance gotcha, a missing runtime
library the image recipe's own comment had misdiagnosed as unnecessary, and
three smaller packaging fixes). One residual finding not yet root-caused:
`duduclaw-kiosk.service` was observed to restart once or twice before
settling into a stable `active`/`running` state on one boot (down from
*always* hitting `StartLimitBurst` permanently before the fix) — tracked as
an open follow-up, not re-claimed as fully stable.
