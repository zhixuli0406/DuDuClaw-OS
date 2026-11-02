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

## Installer stream validation (unreleased)

The live installer's write paths now require Bash `pipefail`; its recipe declares
`bash` as a runtime dependency. Decoder, progress-pipe and disk-write errors stop
before GPT repair or settings injection. Progress reaches 100 only after the
complete stream, progress reader and sync succeed. The whole-disk byte-copy and
PARTUUID contract stays the same. [Host stream regression tests](../appliance/tests/installer/README.md)
cover the failure paths and temporary FIFO cleanup; rebuilding and real blank-disk
installation of both shipping ISOs remain unverified for this change.

## A/B persistent mount identities (unreleased)

Both `duduclaw-image-ab` (base) and `duduclaw-image-appliance` (desktop)
bake `/boot` and `/data` fstab entries in the shared `duduclaw-ab-partflags`
rootfs hook. They reference the existing fixed GPT `PARTUUID`s, not the
filesystem UUIDs created for a new factory image. A normal A/B update replaces
only the inactive root slot; the installed ESP, DATA, and their filesystem
UUIDs must remain intact. Wic sets `--no-fstab-update` on the **root-A**
partition so its ext4 writer cannot replace this fstab with the generated
mount table. The flag does not exclude individual ESP/DATA rows from that
table; putting it on those partitions would not protect the root. Verity uses
the same hook before hashing. Root-A/B selection remains in the signed UKI.

The Wic installed image is also the input to `appliance/tools/make-payload.py`
and to the ISO installer's whole-disk copy, so base/desktop factory installs,
QEMU/GCE installations, and OTA payloads share this rootfs fix. The Debian/mkosi
line already uses stable `PARTLABEL=duduclaw-data` and is unchanged. The older
three-partition `duduclaw-image-data` developer image is not an A/B payload source.

Fixed GPT identities retain the existing single-installation-disk assumption:
do not attach another full DuDuClaw disk with the same `PARTUUID`s while booting.
This does not introduce a global `LABEL=boot` selector or change the disk's
identifiers, layout, signatures, rollback slot, or data. Rebuilding and a real
old-disk OTA/reboot remain required; host fixtures are not boot acceptance.

Run `python3 -B scripts/tests/ab-persistent-mounts.py` from the repository root.
It executes the rootfs hook for verity on/off, checks the old/new filesystem
UUID mismatch, root/unrelated mounts, DATA flags, and the root-A writer flag.
For the engine regression, add `--wic-engine-dir /path/to/wic/src/wic` from
pinned Wic commit `5974ade11032f218841d9f449ef0efeee3f9a2ca`. The test verifies
full source hashes, executes the original `update_fstab` method on temporary
files, and evaluates the original ext4 writer guard. It proves that removing
the root-A flag reopens injection of duplicate mount rows. No upstream source
is copied into this repository and no mkfs, debugfs, disk or guest is used.
Without the source path this engine case is explicitly skipped; the other
checks alone are not engine proof.

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
│                                            #   flatpak-offline-repo, flatpak-setup, flatpak-kiosk-verify, polkit-flatpak,
│                                            #   compat-runners, steam-devices, ai-runtimes, llama-server,
│                                            #   podman (rootless engine for the gateway, desktop edition),
│                                            #   maint (maintenance SSH account, both editions)
├── recipes-containers/container-host-config/ # bbappend: overlay storage + rootless containers.conf drop-in
├── recipes-ai/llama-cpp/                    # llama.cpp v0.4.0 — llama-server / llama-cli (CPU build)
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
│   ├── serial1.yml                          # release overlay: -j1 serial build (OOM guard), SPDX off
│   └── release-linux-builder.yml            # release overlay for a 16 vCPU / 64 GB Linux builder: SPDX off, 8 threads
├── docker/Dockerfile.yocto-builder          # Linux build container for macOS hosts
└── scripts/sb-keygen.sh                     # self-signed PK/KEK/db generation
```

## Images

| Recipe | What it is | Role |
|---|---|---|
| `duduclaw-image-appliance` | **Desktop edition**: A/B update chain + the desktop stack + Flatpak-preloaded Chromium / LibreOffice / Steam + app compatibility layer + rootless Podman (no setuid binaries besides `newuidmap`/`newgidmap`) + read-only root + firewall + login hardening | **Shipping image** — the `.wic.zst` in each release, and the payload of `duduclaw-image-live-desktop` |
| `duduclaw-image-appliance-test` | Same payload, root serial autologin | QEMU test variant, never shipped |
| `duduclaw-image-ab` | **Base image**: A/B GPT layout + update chain on top of `duduclaw-image` (which already carries the desktop stack — comp/shell, IME, audio, XWayland — and the gateway); firewall included since 2026-10-15; no app layer, no container engine, no read-only root | Payload of the `duduclaw-image-live` ISO since v0.1.0; a bring-up artifact |
| `duduclaw-image-live` (+ `-live-initramfs`) | squashfs live environment with the graphical installer; writes the image named by `DUDUCLAW_INSTALL_PAYLOAD_IMAGE` (default `duduclaw-image-ab`) to the target disk | The base-edition installer `.iso`, shipped with every release since v0.1.0 |
| `duduclaw-image-live-desktop` | Same live environment, payload = `duduclaw-image-appliance` (desktop edition) | The desktop-edition installer `.iso` (added 2026-09-04, alongside v0.1.0, and shipped with every release since) |
| `duduclaw-image-flatpak` | Flatpak / bubblewrap / ostree / polkit carriage on top of `-data` | Building block |
| `duduclaw-image-data` | `/data` partition + first-boot provisioning on top of `duduclaw-image` | Building block |
| `duduclaw-image` | `duduclaw-sysd` + `duduclaw` payload on top of `-minimal` | Building block |
| `duduclaw-image-minimal` | Console-only UKI + systemd-boot image | Bring-up / smoke |

### Journal routing

Journald owns `/dev/log` on this systemd distro. The distro clears
`VIRTUAL-RUNTIME_base-utils-syslog`, so core-boot does not recommend
`busybox-syslog`. The `duduclaw-journald` configuration package also
conflicts with `busybox-syslog` and `busybox-klogd` to prevent a later image
dependency from reinstalling competing logging services. Journald reads
kernel records itself; the product does not depend on `/var/log/messages`.

This preserves the original process credentials and systemd metadata used
by maintenance SSH auditing. It does not relax the audit's UID, executable,
slice or message checks. BusyBox's logging applets remain part of the base
utilities; this policy removes the competing service packages.

Rebuilt-image validation must verify that journald's dev-log socket is
active, the legacy services are absent, and a real maintenance SSH login
and logout change the live session count and produce trusted audit events.
The isolated TEST log-route probe reproduced a message reaching the legacy
log file while missing the journal. Runtime plumbing repair and rebuilt
base/desktop image acceptance are separate gates and remain pending.

### Service accounts and privileges

In the layer since 2026-10-15 and shipped in v0.4.0 (rootless gateway; v0.3.0
and earlier ran it as root). Checklist:
[`../wiki/eval/rootless-verification-2026-10.md`](../wiki/eval/rootless-verification-2026-10.md);
evidence from the two QEMU rounds on the qemux86-64 test image:
[`../wiki/reports/rootless-verification/2026-10-15.md`](../wiki/reports/rootless-verification/2026-10-15.md).

| Account / unit | Runs as | Notes |
|---|---|---|
| `duduclaw-gateway.service` | `duduclaw` (uid/gid 1000, fixed) | `NoNewPrivileges`, `RestrictNamespaces`; supplementary groups `duduclaw-ipc`, `duduclaw-kiosk`; `TMPDIR=/data/duduclaw/tmp`; `DOCKER_HOST`/`CONTAINER_HOST` point at the Podman socket |
| `duduclaw-podman.socket`/`.service` (desktop edition) | `duduclaw` | socket `/run/duduclaw-podman/podman.sock` (root 0711 dir); `podman system service`, `Delegate=yes` + `DelegateSubgroup=supervisor`, `KillMode=mixed` (a restart kills running sandboxes), `ProtectSystem=strict` with the gateway home read-only (`XDG_CACHE_HOME` in the store), bounding set `CAP_SETUID CAP_SETGID CAP_DAC_OVERRIDE CAP_SYS_ADMIN` (only setuid newuidmap/newgidmap can use it), no NNP, no `ProtectKernelTunables` (breaks netavark/crun), `InaccessiblePaths=` for root control sockets; store `/data/system/containers/duduclaw`; loads an nftables rule that drops loopback connections from its own cgroup, re-added on firewall reloads without restarting podman |
| `duduclaw-sysd.service` | root | the gateway's only root entry point, `--allowed-uid 1000`; `--require-main-pid-of duduclaw-gateway.service --min-rollback-version …` are appended at build time from `DUDUCLAW_MIN_ROLLBACK_VERSION` (`1.73.4-y1-bringup` since v0.4.0) |
| `duduclaw-home-owner.service` | root, oneshot | `systemd-tmpfiles` with `Z` over `/data/duduclaw` before anything runs as uid 1000 (replaces `chown -R`, which followed symlinks); moves root-only state (machine-id, entropy seed, rescue audit log) to `/data/system` once |
| `duduclaw-factory-reset.service` | root, oneshot | wipes the gateway, kiosk and container data at boot when `/data/system/factory-reset.pending` holds `clear_network=0` or `clear_network=1`, plus the SSH host key (`/data/system/dropbear`), the maintenance SSH audit log with its rotations and lock, and `duduclaw-sysd`'s maintenance SSH state (`/data/system/maint-ssh`); refuses a marker that is not root-owned or is group/world-writable |
| `duduclaw-rollback-prune.service` | root, oneshot | after `boot-complete.target`, deletes ESP entries older than `DUDUCLAW_MIN_ROLLBACK_VERSION` (`conf/distro/include/duduclaw-rollback-floor.inc`, `1.73.4-y1-bringup` since v0.4.0; the unit is skipped while it is empty) — no way back to a pre-rootless image by design |
| `duduclaw-data-migrate.service`, `duduclaw-secaudit-scan.service` | `duduclaw` | they only touch the gateway's own tree |
| `duduclaw-llama-server.service` | `duduclaw` | no `EnvironmentFile=`; `llama-server-run` reads only the four `LLAMA_*` keys from the gateway's settings file as uid 1000 and binds 127.0.0.1 |
| `duduclaw-maint` account (both editions; next image, not in v0.4.0) | — (login account, uid/gid 4800, fixed) | the account a support technician logs in as over SSH during a maintenance window; password field `*`, no supplementary groups, home `/usr/share/duduclaw-maint` (empty, root 0555), shell `/usr/libexec/duduclaw/maint-shell` (a fixed menu from the platform's `duduclaw-maint-tools`, listed in `/etc/shells`); no polkit: the menu's two restarts (gateway, local model server) are done by a root helper service. The current source vendors the platform menu and per-window key handling, and installs the readiness marker; image/QEMU verification is still pending. Build checks: `recipes-core/images/duduclaw-maint-checks.inc` |
| `dropbear.socket` / `dropbear@.service` (next image) | per-connection server, drops to `duduclaw-maint` after auth | off by default; started by `duduclaw-sysd` for a maintenance window. Drop-ins `60-duduclaw-maint.conf`: `-G duduclaw-maint -D /run/duduclaw-maint-ssh -c /usr/libexec/duduclaw/maint-shell -s -j -k -w`, host key `/data/system/dropbear/dropbear_ed25519_host_key` (made by `dropbearkey.service` on `/data`, deleted by factory reset), `IPAddressDeny=any`, `ProtectProc=invisible`, `ProtectSystem=strict`, `BindsTo=duduclaw-sysd.service` on both units. `duduclaw-sysd` falls back on a PID 1 timer running `/usr/libexec/duduclaw/maint-ssh-close` (root) to close a window it could not close itself; the script atomically replaces `/data/system/maint-ssh/last-close.json` (root 0700 dir, temp file + rename) and appends sysd's close-record shape (trigger `fallback_timer`) to `/data/system/maint-ssh-audit.log` under the same `flock` on `<file>.lock` (root 0600, 10 s bound), never rotates, and refuses to write if the log or lock is not a root-owned 0600 regular file. The build checks the `ExecStart` token by token, that no host key is baked in, and that the kernel has `CONFIG_CGROUP_BPF`. Firewall: port 22 (when sysd puts it in `maintenance_tcp_ports`) is accepted only from `maintenance_src4` (RFC 1918, 169.254.0.0/16, 100.64.0.0/10) and `maintenance_src6` (fc00::/7, fe80::/10), every other source gets a TCP reset; `duduclaw-maint`'s `nftables.service.d/60-duduclaw-maint.conf` adds `meta skuid 4800 counter reject` to the `duduclaw_maint_egress` loopback chain (jumped to by the first rule of `output`, before the podman chain) on every start and reload (numeric uid, never a name in `nftables.conf`) |
| `duduclaw-maint-helper.socket` / `duduclaw-maint-helper@.service` (next image) | root, one instance per connection | the maintenance menu's only root entry point (no polkit, no sudo): `/run/duduclaw-maint-helper.sock` root:duduclaw-maint 0660, `Accept=yes`, at most 4 connections; the instance runs `/usr/libexec/duduclaw/maint-helper` (platform `duduclaw-maint-tools`; checks the peer is uid 4800, accepts six tokens: gateway/model logs with or without follow, `restart-gateway`, `restart-model`, rate-limited) with an empty `CapabilityBoundingSet=`, `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectProc=invisible`, `PrivateNetwork`, `IPAddressDeny=any`, `RestrictAddressFamilies=AF_UNIX`, `SystemCallFilter=@system-service`, the `ProtectKernel*`/`ProtectControlGroups`/`ProtectClock`/`ProtectHostname`/`PrivateDevices`/`ProtectHome`/`PrivateTmp`/`RestrictNamespaces`/`LockPersonality`/`MemoryDenyWriteExecute` set, `RuntimeMaxSec=3600`, writable only `RuntimeDirectory=duduclaw-maint-helper` (0700, kept between instances; the helper keeps its restart rate limit there), `CollectMode=inactive-or-failed`, its own slice (not `system-dropbear.slice`), stderr to the journal |
| `duduclaw-kiosk.service` | `duduclaw-kiosk` | comp's shell-control/codrive sockets (0660) and codrive token (0640) belong to group `duduclaw-ipc` (members: the kiosk user and `duduclaw`); the gateway sets volume through comp's `get_audio`/`set_audio`/`set_audio_output` verbs, PipeWire sockets stay 0600 |

For the next image, the factory-reset oneshot is ordered before
`duduclaw-sysd.service` and `dropbearkey.service`. This prevents sysd from
writing old window/audit data back after the wipe, and prevents a completed
host-key generation from losing its key to a concurrent wipe. These are
ordering dependencies only; a failed reset does not block the two services
or the dashboard from starting.

Run `python3 scripts/tests/maint-reset-order.py` to check the explicit
ordering graph in the layer's unit sources, including cycle and failure
dependency checks. This is a static regression test; it does not include
upstream units or generated systemd dependencies, and does not replace an
image build or QEMU boot.

The fallback close script reads the platform sysd's persistent
`/data/system/maint-ssh/window.json`, never a file in the tmpfs key directory.
It leaves that state file unchanged so sysd can replay the journal from its
saved cursor, including after a reboot when the tmpfs key has disappeared.
With neither a persistent window nor a key, it does not write an audit record
or replace `last-close.json`.

The regression test uses real bash, files and `flock`, with substitutes for
`systemctl` and `nft`; it does not exercise a booted image or the firewall.
It compares the fixture's fields and paths against the supplied platform
checkout's `crates/duduclaw-sysd/src/maint_ssh/mod.rs` (`WindowFile`, `STATE_DIR`,
`KEY_DIR`, `WINDOW_FILE`). Run in a disposable Linux container as root:

```sh
docker run --rm --network none \
  -v "$PWD:/repo:ro" -v "$PWD/../DuDuClaw:/platform:ro" \
  python:3.12-slim python3 /repo/scripts/tests/maint-ssh-close.py --platform-root /platform
```

The platform checkout must match the vendored revision in
`conf/distro/include/duduclaw-platform-version.inc`. The current source uses
platform v1.74.0 at `a1f5fd6a964a17c2d3ad9e1165f6df3a8586c213`. Its CLI recipe
builds `duduclaw-cli` and `duduclaw-maint-tools` in one workspace build, then
packages the menu/helper separately as `duduclaw-maint-tools`; `duduclaw-maint`
depends on that package and installs `/usr/lib/duduclaw/maint-ssh.ready` with
content `1` and a newline. The menu binary is 0755, the root-only helper 0700.
The tools package includes iproute2, procps and coreutils so diagnostics use
the expected command options; no new account comes from the tools package.

The security snapshot uses zip 9.0.4, rust_xlsxwriter 0.100.0 and the platform's
checksum-pinned calamine patch, copied by the unmodified refresh script. The
CLI registry set has changed: its crate-fetch include was regenerated by the
original BitBake `update_crates` task. All 785 entries and checksums match the
snapshot lock exactly. Image builds and real installations remain pending.

The final rootfs gate refuses missing, writable or linked tools, old gateway
or sysd protocol binaries, an invalid marker, or any `authorized_keys` path.
The preceding account, dropbear, nftables and helper-unit checks remain
required. Fast fixture/source checks (no compilation or image build):

```sh
python3 scripts/tests/maint-readiness.py
python3 scripts/tests/platform-snapshot.py --platform-root ../DuDuClaw
```

The fixture's tiny stand-ins are not actual binaries; these checks do not
replace BitBake package QA, a complete image build or QEMU tests.

A/B image builds stop at `do_rootfs` if `DUDUCLAW_MIN_ROLLBACK_VERSION` is
empty (no platform guards). With it set, as in v0.4.0, A/B updates install
from the root-owned `/data/system/updates`. `/data` is mounted `nosuid,nodev`.
The iwd D-Bus policy for `duduclaw` covers only Station, Network,
KnownNetwork, AgentManager and property reads.

The image build fails if any polkit rules file mentions `duduclaw-maint`,
if uid/gid 4800 is used by anything but `duduclaw-maint`, if 4800 falls inside the host's dynamic system range
(101–999), a subordinate id range, the Android ids Waydroid uses on the
host or systemd's reserved ranges, or if any account changed its id, went
away or appeared since the previous release. The previous release's table
is `recipes-core/images/duduclaw-image-ab/account-ids.txt` (base edition)
and `recipes-core/images/duduclaw-image-appliance/account-ids.txt`
(desktop edition), dumped from the published v0.4.0 images; regenerate
both after each release (the files' headers say how) and empty
`DUDUCLAW_ACCOUNT_IDS_ADDED`.

Adding a system account or group (any recipe with `inherit useradd`):
give it a fixed id (`--uid`/`--gid`) outside 101–999, 100000–165535, the
Android id ranges and systemd's reserved ranges, and outside every id in
the two tables; a dynamic id (no `--uid`) is assigned by install order and
can move every dynamic account installed after it. List the new names in
`DUDUCLAW_ACCOUNT_IDS_ADDED` (`user:<name>` / `group:<name>`, in
`duduclaw-maint-checks.inc`) in the same commit, or the image build fails.
A package newly pulled into an edition can also bring a dynamic account
with it, and install order then moves the others (in the desktop edition
polkit's `polkitd` is 999 and everything after it one lower than in the
base edition); the comparison catches that as a moved or new id. The ids are not pinned with
`useradd-staticids`: that class rewrites each recipe's `useradd` call for
the whole build, and the two editions already have different ids for
every dynamic account (base `duduclaw-kiosk` 999:997, desktop 998:996;
base `polkitd` 996:991, desktop 999:999; see the two tables), so one table
cannot keep both.

The Flatpak polkit grant now keys on the empty `duduclaw-flatpak` group, so
the gateway has no Flatpak rights. `duduclaw-cli` ships
`fs.protected_hardlinks/symlinks=1` and `kernel.yama.ptrace_scope=1`.
`runuser` is not in the image (util-linux builds it only with PAM); act as
the gateway with `setpriv --reuid=duduclaw --regid=duduclaw --init-groups`.

The unreleased firewall policy permits DHCPv6 client bootstrap replies only
between IPv6 link-local addresses (UDP source 547, destination 546). Existing
SSH source restrictions and egress policy are unchanged. See the
[packet regression and image-validation boundary](../appliance/tests/firewall/README.md).

Shared payload sets:
`duduclaw-image-{data,flatpak,desktop,compat,runtimes,local-model}.inc`;
read-only root wiring: `duduclaw-ro-root.inc`.
`duduclaw-image-runtimes.inc` (the AI payload: `nodejs` + `nodejs-npm`,
`duduclaw-ai-runtimes`, `llama-cpp`, `duduclaw-llama-server`) is required
only by `duduclaw-image-appliance` — deliberately not by `desktop.inc`,
which `duduclaw-image-live` shares, so ~2 GB of coding agents stays out of
the installer ISO. It is also why `DUDUCLAW_AB_SLOT_SIZE_MB` is 8192 on the
appliance image; see [`../docs/guides/ai-runtimes.md`](../docs/guides/ai-runtimes.md)
for the budget and the refresh procedure. Secure Boot signing and
dm-verity are enabled by the `kas/sb-signing.yml` overlay, TPM2 + LUKS by
`kas/tpm-luks.yml`; a build without those overlays (which is what
`scripts/release-os.sh build` does today, and what every release through
v0.4.0 has shipped) produces unsigned UKIs, no verity partition and no TPM
stack. Release builds do chain `kas/serial1.yml` by default (SPDX off,
`-j1`), or `kas/release-linux-builder.yml` on a large Linux builder (SPDX
off, 8 parallel tasks; v0.3.0 was built with it, and so was the v0.4.0
test build) — neither overlay touches
the trust chain.

## Usage

The release pipeline (`scripts/release-os.sh build / smoke / package /
publish`, see the repo-root README) wraps everything below with builder
concurrency guards. It currently passes only the base kas config, so signed /
verity / TPM builds and the SPDX-off `serial1.yml` overlay have to be added by
hand (`kas build a.yml:b.yml`); the manual steps below are for development
and debugging.

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
already up, refuses to start a build while another kas/bitbake process
is in flight, and refuses when the Mac volume holding `$HOME` has less than
`DUDUCLAW_MIN_HOST_FREE_GB` (30) GB free — Docker Desktop's sparse
`Docker.raw` grows on that volume and the engine crashes mid-image when it
fills (seen 2026-09-06).

### Build

```bash
# qemux86-64, image selected via KAS_TARGET (the kas file's own target: field is not the source of truth)
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && KAS_TARGET=duduclaw-image-appliance kas build meta-duduclaw/kas/duduclaw-os.yml"

# real hardware
docker exec -u 1000 duduclaw-yocto bash -c \
    "cd /workspace && KAS_TARGET=duduclaw-image-appliance kas build meta-duduclaw/kas/duduclaw-os-genericx86-64.yml"
```

For `duduclaw-genericx86-64`, `duduclaw-gce-guest.cfg` requests
`HYPERVISOR_GUEST`, `PARAVIRT`, `KVM_GUEST` and `PARAVIRT_CLOCK` as built-ins.
The final kernel `.config` is checked after configuration, before compilation;
a missing or modular guest dependency, VirtIO PCI/SCSI/network driver or PCI
MSI option aborts the build. This follows the [GCE custom-kernel
requirements](https://cloud.google.com/compute/docs/images/building-custom-os).
The existing host KVM modules are unchanged. Run the host regression with
`python3 scripts/tests/gce-kernel-guest.py` from the repository root. This
configuration check is not evidence of a successful native GCE boot or install.

Do not run two kas configs concurrently in one build dir: they rewrite the
same `build/conf/local.conf` and bitbake fails with cascading
"metadata not deterministic" errors.

### Boot under QEMU

The installed initramfs mounts `/run` tmpfs with explicit `mode=0755` before
handing it to systemd. Existing mounts retain their mode; strict Dropbear
authorized-key ancestor checks reject a writable `/run`. The patch regression
(`python3 scripts/tests/initramfs-run-mode.py`) does not replace runtime `/run`
and normal maintenance-login verification on the rebuilt guest.

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

See the repo-root [`CHANGELOG.md`](../CHANGELOG.md). v0.1.0 (2026-09-04) was
the first tagged bring-up release; v0.2.0 (2026-09-09) resynced the
embedded platform snapshot to v1.63.0; v0.3.0 (2026-10-13, published
2026-10-14) resynced it to v1.73.1 with `duduclaw-shell` 1.65.3 and was the
first release built on the GCP Linux builder; v0.4.0 (2026-10-16) resynced
it to v1.73.4 and moved the gateway to the unprivileged `duduclaw` account
with rootless Podman (a one-way upgrade: no rollback below v0.4.0). Every
release publishes, per machine, all three artifact forms (the whole-disk
image, the base-edition installer ISO, and the desktop-edition installer
ISO), each signed. For v0.4.0, as for v0.3.0, the QEMU machine's
whole-disk image reached the login prompt and its two installer ISOs
reached the live environment's automatic login under headless QEMU; the
installer wizard was not run. The real-hardware machine
(`duduclaw-genericx86-64`) was built but not booted — it has not yet been
booted on real hardware.

Unreleased: `duduclaw-image-local-model.inc` adds `duduclaw-llama-server`
to the base A/B image; its hard dependency supplies `llama-cpp`. It also
checks the real engine, wrapper and service payload for both shipping
editions. The desktop runtime bundle remains separate, and model weights
stay on `/data`. Image and runtime acceptance for this change is pending.
