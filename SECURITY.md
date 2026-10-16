# Security Policy

## Supported Versions

DuDuClaw OS is in bring-up (`0.x`, pre-GA). Only the latest tagged release
receives fixes; there is no long-term support line yet.

| Version | Supported |
|---------|-----------|
| Latest tagged release (`v0.x`) | :white_check_mark: |
| Older tags | :x: |

## Reporting a Vulnerability

**Do NOT open a public GitHub issue for security vulnerabilities.**

### Preferred: GitHub Private Vulnerability Reporting

1. Go to the [Security Advisories](https://github.com/zhixuli0406/DuDuClaw-OS/security/advisories) page
2. Click **"Report a vulnerability"**
3. Fill in the details and submit

### Alternative: Email

Send an email to **louis.li@dudustudio.monster** with the subject
`[SECURITY] Brief description`, the affected release (tag and machine), the
impact, and minimal steps to reproduce.

Response timeline and disclosure handling follow the platform repo's
[SECURITY.md](https://github.com/zhixuli0406/DuDuClaw/blob/main/SECURITY.md).

## Scope

In scope for this repo:

- The Yocto layer (`meta-duduclaw/`): image recipes, boot chain, A/B
  update chain, Secure Boot / dm-verity / TPM wiring, firewall and
  hardening, first-boot provisioning.
- The release pipeline (`scripts/release-os.sh`) and the published
  release artifacts.

Out of scope here (report to the platform repo instead): vulnerabilities in
the DuDuClaw gateway, dashboard, or `duduclaw-*` binaries — the sources
under `meta-duduclaw/recipes-duduclaw/*/files/*-src/` are vendored
snapshots of the [DuDuClaw platform](https://github.com/zhixuli0406/DuDuClaw).

The frozen `appliance/` Debian/mkosi line is not shipped and is not
maintained for security fixes.

## Release Artifact Security

Every release publishes, per machine, three artifact forms:

- a whole-disk image (`duduclaw-os-<machine>-v<version>.wic.zst`, the
  desktop edition),
- a base-edition installer ISO (`duduclaw-os-installer-<machine>-v<version>.iso`),
- a desktop-edition installer ISO
  (`duduclaw-os-installer-desktop-<machine>-v<version>.iso`).

Every one of the three ships with a `.sha256` sidecar and a `.minisig`
signature made with the OS release key, whose public key is pinned in
`scripts/release-os.sh` (`OS_RELEASE_PUBKEY`) and re-verified fail-closed
before anything is uploaded. The whole-disk image additionally ships a
`.manifest.json` recording the OS version, the embedded platform version,
the machine, and the image recipe; the two installer ISOs do not carry one.

Verify before flashing:

```bash
minisign -V -P RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n -m <file>
shasum -a 256 -c <file>.sha256
```

Artifacts are distributed only via GitHub Releases on this repo. The build
layer supports Secure Boot signing with self-signed keys, dm-verity root
verification and TPM2-sealed LUKS as build-time overlays; every release
through v0.4.0 has been built without them (unsigned UKIs, no verity
partition, no TPM stack — see the README's Trust chain section). The
desktop edition ships with a read-only root.

## Runtime Privilege Model

Shipped in v0.4.0 (2026-10-16), both editions; v0.3.0 and earlier ran the
gateway as root. Checked under QEMU on the qemux86-64 test variant of the
desktop image in two rounds (the second passed 35 of 36 checks; evidence in
`wiki/reports/rootless-verification/2026-10-15.md`). Not yet verified: the
A/B upgrade from a v0.3.0 device, the LLM-backed container flows, and real
hardware.

- The DuDuClaw gateway, every AI CLI it runs and the local model server
  execute as the unprivileged `duduclaw` account (uid 1000) with
  `NoNewPrivileges`. AI employees share that uid, so the design assumes an
  attacker who controls uid 1000. Root services do not read configuration
  from that account's home; where root needs a value from it (the boot
  health check's gateway port in `config.toml`), it is read as uid 1000
  with a size cap and a timeout. Root login shells run `duduclaw` and the
  bundled AI CLIs through `setpriv` as uid 1000 with no new privileges, and
  the kernel refuses TIOCSTI keystroke injection to unprivileged callers;
  that shell function covers interactive login shells only (`sh -c
  duduclaw` runs as root). `duduclaw-sysd` is the only root service the
  gateway can call. The A/B images (`duduclaw-image-ab` and the desktop
  edition built on it) are refused at build time unless the platform
  release in which sysd also checks that the caller is the gateway's main
  process is vendored. Non-A/B development images
  (`duduclaw-image`, `-data`, `-flatpak`) are not refused and run sysd with
  the uid check only.
- A/B updates install only from the root-owned `/data/system/updates`,
  filled by `duduclaw-sysd` after it verified the release signature and the
  version. The gateway reaches the kiosk's audio through three fixed
  compositor verbs, not through the PipeWire socket; its Wi-Fi access is
  limited to the iwd interfaces the network page uses. `/data` is mounted
  `nosuid,nodev`.
- The desktop edition runs containers with rootless Podman as the same
  account. Every setuid/setgid bit in the image is removed except on
  `newuidmap`/`newgidmap`, and the build fails if another one survives, if
  any file carries file capabilities, or if first-boot postinsts are left
  that could add either back. A
  firewall rule drops connections that containers (through pasta) open
  towards services on the host itself.
- Ownership of the gateway's data is repaired at boot with
  `systemd-tmpfiles` (never follows symlinks), not `chown -R`; root-only
  state (machine-id, entropy seed, rescue audit log) lives in
  `/data/system`, outside the gateway's home.
- Once a rootless image has passed the boot health gate, ESP entries older
  than the configured rollback floor are deleted, so neither a requested
  rollback nor systemd-boot's automatic fallback can bring back an image
  whose gateway ran as root. By design there is no way back to a
  pre-rootless image after that. The floor is `1.73.4-y1-bringup`, the
  image version of v0.4.0 itself. Known gap: before the first rootless
  image is blessed, code running as uid 1000 on it can make its trial boots
  fail and so trigger systemd-boot's fallback to the previous image.
- SSH (dropbear) is off by default on both editions. The dashboard's
  maintenance mode starts it and opens port 22 in the default-deny
  firewall; closing the window stops dropbear, ends every session and
  closes the port. No account can log in over SSH yet (root is locked), so
  the switch currently controls only the port.
- Maintenance SSH login (in the layer, lands in the next OS image, not in
  v0.4.0): a dedicated account, `duduclaw-maint`, with a fixed uid/gid of
  4800, password field `*`, no supplementary groups, an empty read-only
  home and a fixed menu as its login shell instead of a general shell. Its
  only actions are restarting the gateway or the local model server, done
  by a root helper service on its behalf (no polkit, no sudo). The image
  build fails if 4800 is used by any other
  account or falls inside the host's dynamic system ids, the gateway's
  subordinate ids, the Android ids Waydroid runs as host ids, or systemd's
  reserved ranges, and if any account changed its id against the previous
  release (an id that moves leaves files on `/data` owned by the wrong
  account after an A/B update). The account cannot log in until the
  platform snapshot that carries the menu and the per-window key handling
  is vendored into the image.
  dropbear (same next image) lets only that account's group log in
  (`-G duduclaw-maint`), only with a public key (`-s`), reads authorized
  keys only from `/run/duduclaw-maint-ssh` (tmpfs, written by
  `duduclaw-sysd` for one window), runs the menu for every session
  whatever the client asks (`-c`, which also replaces scp and sftp), and
  refuses port forwarding (`-j -k`). Sessions run with
  `IPAddressDeny=any`, `NoNewPrivileges`, `ProtectProc=invisible`,
  `ProtectSystem=strict` and no access to the gateway's and kiosk's homes,
  saved Wi-Fi networks or the container store. Both the listening socket
  and the sessions are bound to `duduclaw-sysd.service`, so they stop if
  sysd stops or fails for good. The build fails if the kernel lacks
  `CONFIG_CGROUP_BPF` (without it systemd skips `IPAddressDeny=` with only
  a warning), if the dropbear command differs from the expected one, or if
  a host key is baked into the image. The host key is one ed25519 key in
  `/data/system/dropbear`, generated on the device (the desktop edition's
  root is read-only) and deleted by a factory reset together with the
  maintenance SSH audit log. If sysd does not close a window in time, a
  timer in PID 1 runs a root script that deletes the key, stops dropbear,
  removes port 22 from the firewall and writes the audit record. Residual
  risk: the script tries that audit write once. If the audit file or its
  lock is not a root-owned 0600 file, or the lock is held for more than
  10 seconds, the record is not written (the reason goes to the journal)
  and is not retried; the window is still closed, and sysd's next startup
  cleanup writes its own close record from the state it kept.
- What remains: kernel bugs reachable from an unprivileged user namespace,
  and whatever `duduclaw-sysd`'s request handlers allow a uid-1000 caller to
  do (that code is in the platform repo).

## Disclosure Policy

We follow [coordinated vulnerability disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure):
give us reasonable time to fix the issue before public disclosure, and do
not exploit a vulnerability beyond what is necessary to demonstrate it.
