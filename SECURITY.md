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
through v0.2.0 has been built without them (unsigned UKIs, no verity
partition, no TPM stack — see the README's Trust chain section). The
desktop edition ships with a read-only root.

## Disclosure Policy

We follow [coordinated vulnerability disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure):
give us reasonable time to fix the issue before public disclosure, and do
not exploit a vulnerability beyond what is necessary to demonstrate it.
